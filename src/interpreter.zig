const std = @import("std");
const ast = @import("ast.zig");
const Value = @import("value.zig").Value;
const proc = @import("process.zig");

pub const Interpreter = struct {
    alloc: std.mem.Allocator,
    modules: std.StringHashMapUnmanaged(ast.ModuleDecl),
    process_decls: std.StringHashMapUnmanaged(ast.ProcessDecl),
    scheduler: proc.Scheduler,
    current_process: ?proc.ProcessId,

    pub const Error = error{
        RuntimeError,
        GuardFailed,
        ReturnValue,
        UndefinedVariable,
        UndefinedFunction,
        UndefinedModule,
        UndefinedProcess,
        UndefinedHandler,
        MailboxFull,
        ProcessDead,
        TypeError,
        OutOfMemory,
    };

    pub const Result = struct {
        value: Value,
        returned: bool,
    };

    pub fn init(alloc: std.mem.Allocator) Interpreter {
        return .{
            .alloc = alloc,
            .modules = .{},
            .process_decls = .{},
            .scheduler = proc.Scheduler.init(alloc),
            .current_process = null,
        };
    }

    // ── Load declarations ─────────────────────────────────────

    pub fn load(self: *Interpreter, file: ast.File) !void {
        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| try self.modules.put(self.alloc, m.name, m),
                .process_decl => |p| try self.process_decls.put(self.alloc, p.name, p),
                .type_decl => {},
                .struct_decl => {},
            }
        }
    }

    // ── Find entry point ───────────────────────────────────────

    pub const EntryPoint = struct {
        module: []const u8,
        name: []const u8,
        is_process: bool,
    };

    pub fn findMain(self: *Interpreter) ?EntryPoint {
        // Check processes first (preferred entry point)
        var proc_iter = self.process_decls.iterator();
        while (proc_iter.next()) |entry| {
            for (entry.value_ptr.receive_handlers) |handler| {
                if (std.mem.eql(u8, handler.name, "main")) {
                    return .{ .module = entry.key_ptr.*, .name = "main", .is_process = true };
                }
            }
        }
        // Fall back to module functions
        var mod_iter = self.modules.iterator();
        while (mod_iter.next()) |entry| {
            for (entry.value_ptr.functions) |func| {
                if (std.mem.eql(u8, func.name, "main")) {
                    return .{ .module = entry.key_ptr.*, .name = "main", .is_process = false };
                }
            }
        }
        return null;
    }

    // ── Run a process entry point ─────────────────────────────

    pub fn runProcessMain(self: *Interpreter, process_name: []const u8, args: []const Value) Error!Value {
        const decl = self.process_decls.get(process_name) orelse return error.UndefinedProcess;

        // Spawn the main process
        const pid = self.scheduler.spawn(process_name, decl) catch return error.OutOfMemory;
        self.current_process = pid;

        // Find main fn in the process (it's stored as a receive handler for now)
        const handler = blk: {
            for (decl.receive_handlers) |h| {
                if (std.mem.eql(u8, h.name, "main")) break :blk h;
            }
            return error.UndefinedHandler;
        };

        // Execute main with process scope
        return try self.execReceiveHandler(pid, handler, args);
    }

    fn execReceiveHandler(self: *Interpreter, pid: proc.ProcessId, handler: ast.ReceiveDecl, args: []const Value) Error!Value {
        const saved_process = self.current_process;
        self.current_process = pid;
        defer self.current_process = saved_process;

        var scope = Scope.init(self.alloc);

        // Bind parameters
        for (handler.params, 0..) |param, i| {
            if (i < args.len) {
                try scope.set(param.name, args[i]);
            }
        }

        // Evaluate guards
        for (handler.guards) |guard_expr| {
            const guard_val = try self.evalExpr(guard_expr, &scope);
            if (!guard_val.isTruthy()) {
                return .{ .tag_with_value = .{
                    .tag = "error",
                    .values = try self.allocValues(&.{.{ .tag = "guard_failed" }}),
                } };
            }
        }

        // Execute body
        const result = try self.execBlock(handler.body, &scope);
        if (result.returned) return result.value;
        return result.value;
    }

    // ── Spawn a process ───────────────────────────────────────

    fn spawnProcess(self: *Interpreter, name: []const u8) Error!Value {
        const decl = self.process_decls.get(name) orelse return error.UndefinedProcess;
        const pid = self.scheduler.spawn(name, decl) catch return error.OutOfMemory;
        return .{ .process_id = pid };
    }

    // ── Send a message to a process ───────────────────────────

    fn sendToProcess(self: *Interpreter, target_pid: proc.ProcessId, handler_name: []const u8, args: []const Value) Error!Value {
        const target = self.scheduler.getProcess(target_pid) orelse return error.ProcessDead;
        if (!target.alive) return error.ProcessDead;

        const handler = target.findHandler(handler_name) orelse return error.UndefinedHandler;

        // Single-threaded: execute the handler directly
        const result = try self.execReceiveHandler(target_pid, handler, args);

        // Wrap in Result<T> — :ok{value} or :error{reason}
        if (result == .tag_with_value and std.mem.eql(u8, result.tag_with_value.tag, "error")) {
            return result; // already an error
        }

        return .{ .tag_with_value = .{
            .tag = "ok",
            .values = try self.allocValues(&.{result}),
        } };
    }

    fn tellProcess(self: *Interpreter, target_pid: proc.ProcessId, handler_name: []const u8, args: []const Value) Error!void {
        const target = self.scheduler.getProcess(target_pid) orelse return;
        if (!target.alive) return;

        const handler = target.findHandler(handler_name) orelse return;

        // Single-threaded: execute immediately, ignore result
        _ = try self.execReceiveHandler(target_pid, handler, args);
    }

    // ── Call a module function ─────────────────────────────────

    pub fn callFunction(self: *Interpreter, module_name: []const u8, fn_name: []const u8, args: []const Value) Error!Value {
        const mod = self.modules.get(module_name) orelse return error.UndefinedModule;

        for (mod.functions) |func| {
            if (std.mem.eql(u8, func.name, fn_name)) {
                return try self.execFunction(func, args);
            }
        }

        return error.UndefinedFunction;
    }

    fn execFunction(self: *Interpreter, func: ast.FnDecl, args: []const Value) Error!Value {
        // Set up scope with parameters
        var scope = Scope.init(self.alloc);

        for (func.params, 0..) |param, i| {
            if (i < args.len) {
                try scope.set(param.name, args[i]);
            }
        }

        // Evaluate guards
        for (func.guards) |guard_expr| {
            const guard_val = try self.evalExpr(guard_expr, &scope);
            if (!guard_val.isTruthy()) {
                return .{ .tag_with_value = .{
                    .tag = "error",
                    .values = try self.allocValues(&.{.{ .tag = "guard_failed" }}),
                } };
            }
        }

        // Execute body
        const result = try self.execBlock(func.body, &scope);
        if (result.returned) return result.value;

        return result.value;
    }

    // ── Execute statements ────────────────────────────────────

    fn execBlock(self: *Interpreter, stmts: []const ast.Stmt, scope: *Scope) Error!Result {
        var last_value: Value = .{ .void = {} };

        for (stmts) |stmt| {
            const result = try self.execStmt(stmt, scope);
            last_value = result.value;
            if (result.returned) return result;
        }

        return .{ .value = last_value, .returned = false };
    }

    fn execStmt(self: *Interpreter, stmt: ast.Stmt, scope: *Scope) Error!Result {
        switch (stmt) {
            .assign => |a| {
                const val = try self.evalExpr(a.value, scope);
                try scope.set(a.name, val);
                return .{ .value = val, .returned = false };
            },
            .return_stmt => |r| {
                const val = if (r.value) |v| try self.evalExpr(v, scope) else Value{ .void = {} };
                return .{ .value = val, .returned = true };
            },
            .while_stmt => |w| {
                while (true) {
                    const cond = try self.evalExpr(w.condition, scope);
                    if (!cond.isTruthy()) break;
                    const result = try self.execBlock(w.body, scope);
                    if (result.returned) return result;
                }
                return .{ .value = .{ .void = {} }, .returned = false };
            },
            .match_stmt => |m| {
                return try self.execMatch(m, scope);
            },
            .expr_stmt => |e| {
                const val = try self.evalExpr(e, scope);
                return .{ .value = val, .returned = false };
            },
            .transition => |t| {
                if (self.current_process) |pid| {
                    if (self.scheduler.getProcess(pid)) |p| {
                        // transition target is a state field name or index expression
                        const target_name = switch (t.target) {
                            .identifier => |id| id,
                            .index_access => |ia| switch (ia.target.*) {
                                .identifier => |id| id,
                                else => return error.RuntimeError,
                            },
                            else => return error.RuntimeError,
                        };
                        // For simple transitions: transition balance { balance + amount; }
                        if (t.fields.len == 1 and t.fields[0].name == null) {
                            const new_val = try self.evalExpr(t.fields[0].value, scope);
                            try p.setState(target_name, new_val);
                        } else {
                            // Named field transitions: transition accounts[id] { balance: X; active: false; }
                            // TODO: implement struct field transitions
                            for (t.fields) |field| {
                                if (field.name) |fname| {
                                    _ = fname;
                                    const new_val = try self.evalExpr(field.value, scope);
                                    try p.setState(target_name, new_val);
                                }
                            }
                        }
                    }
                }
                return .{ .value = .{ .void = {} }, .returned = false };
            },
            .append => |a| {
                const target = try self.evalExpr(a.target, scope);
                const value = try self.evalExpr(a.value, scope);
                if (target == .list) {
                    target.list.append(value) catch return error.OutOfMemory;
                }
                return .{ .value = .{ .void = {} }, .returned = false };
            },
            .send_stmt => return .{ .value = .{ .void = {} }, .returned = false },
            .tell_stmt => |t| {
                // tell — fire and forget, execute handler, ignore result
                const target_val = try self.evalExpr(t.target, scope);
                if (target_val == .process_id) {
                    var args_buf: [64]Value = undefined;
                    var arg_count: usize = 0;
                    for (t.args) |arg_expr| {
                        args_buf[arg_count] = try self.evalExpr(arg_expr, scope);
                        arg_count += 1;
                    }
                    self.tellProcess(target_val.process_id, t.handler, args_buf[0..arg_count]) catch {};
                } else if (target_val == .void) {
                    // Old stub path — target wasn't parsed properly
                }
                return .{ .value = .{ .void = {} }, .returned = false };
            },
            .receive_stmt => {
                // receive; — process one message from our mailbox
                if (self.current_process) |pid| {
                    if (self.scheduler.getProcess(pid)) |p| {
                        if (p.popMessage()) |msg| {
                            // Find and execute the matching handler
                            if (p.findHandler(msg.handler_name)) |handler| {
                                _ = try self.execReceiveHandler(pid, handler, msg.args);
                            }
                        }
                        // If no message, receive; is a no-op in single-threaded interpreter
                        // In real runtime, this would block
                    }
                }
                return .{ .value = .{ .void = {} }, .returned = false };
            },
            .watch_stmt => |w| {
                const target_val = try self.evalExpr(w.target, scope);
                if (target_val == .process_id) {
                    if (self.current_process) |my_pid| {
                        self.scheduler.watch(my_pid, target_val.process_id) catch {};
                    }
                }
                return .{ .value = .{ .void = {} }, .returned = false };
            },
        }
    }

    fn execMatch(self: *Interpreter, m: ast.MatchStmt, scope: *Scope) Error!Result {
        const subject = try self.evalExpr(m.subject, scope);

        for (m.arms) |arm| {
            if (try self.matchPattern(arm.pattern, subject, scope)) {
                return try self.execBlock(arm.body, scope);
            }
        }

        return .{ .value = .{ .void = {} }, .returned = false };
    }

    fn matchPattern(self: *Interpreter, pattern: ast.Pattern, subject: Value, scope: *Scope) Error!bool {
        _ = self;
        switch (pattern) {
            .wildcard => return true,
            .literal => |expr_val| {
                // For bool literals in match
                switch (expr_val) {
                    .bool_literal => |b| {
                        if (subject == .bool) return subject.bool == b;
                        return false;
                    },
                    .int_literal => |i| {
                        if (subject == .int) return subject.int == i;
                        return false;
                    },
                    .tag => |t| {
                        if (subject == .tag) return std.mem.eql(u8, subject.tag, t);
                        return false;
                    },
                    else => return false,
                }
            },
            .tag => |t| {
                // Match :ok{value} pattern
                if (subject == .tag and t.bindings.len == 0) {
                    return std.mem.eql(u8, subject.tag, t.tag);
                }
                if (subject == .tag_with_value) {
                    if (!std.mem.eql(u8, subject.tag_with_value.tag, t.tag)) return false;
                    // Bind values to names
                    for (t.bindings, 0..) |binding, i| {
                        if (i < subject.tag_with_value.values.len) {
                            try scope.set(binding, subject.tag_with_value.values[i]);
                        }
                    }
                    return true;
                }
                return false;
            },
        }
    }

    // ── Evaluate expressions ──────────────────────────────────

    pub fn evalExpr(self: *Interpreter, expr: ast.Expr, scope: *Scope) Error!Value {
        switch (expr) {
            .int_literal => |v| return .{ .int = v },
            .float_literal => |v| return .{ .float = v },
            .string_literal => |v| return .{ .string = v },
            .bool_literal => |v| return .{ .bool = v },
            .tag => |v| return .{ .tag = v },
            .none_literal => return .{ .none = {} },
            .void_literal => return .{ .void = {} },

            .identifier => |name| {
                // Check local scope first
                if (scope.get(name)) |v| return v;
                // Check current process state
                if (self.current_process) |pid| {
                    if (self.scheduler.getProcess(pid)) |p| {
                        if (p.getState(name)) |v| return v;
                    }
                }
                return error.UndefinedVariable;
            },

            .binary_op => |op| return try self.evalBinaryOp(op, scope),
            .unary_op => |op| return try self.evalUnaryOp(op, scope),

            .field_access => |fa| {
                const target = try self.evalExpr(fa.target.*, scope);
                // .len on lists and strings
                if (std.mem.eql(u8, fa.field, "len")) {
                    if (target == .list) return .{ .int = @intCast(target.list.len()) };
                    if (target == .string) return .{ .int = @intCast(target.string.len) };
                    if (target == .map) return .{ .int = @intCast(target.map.len()) };
                }
                if (target == .struct_val) {
                    for (target.struct_val.field_names, 0..) |fname, i| {
                        if (std.mem.eql(u8, fname, fa.field)) {
                            return target.struct_val.field_values[i];
                        }
                    }
                    return error.UndefinedVariable;
                }
                return error.UndefinedVariable;
            },

            .index_access => |ia| {
                const target = try self.evalExpr(ia.target.*, scope);
                const index = try self.evalExpr(ia.index.*, scope);
                if (target == .list and index == .int) {
                    const idx = index.int;
                    if (idx < 0 or idx >= @as(i64, @intCast(target.list.len()))) {
                        return .{ .out_of_bounds = {} };
                    }
                    return target.list.get(@intCast(@as(u64, @intCast(idx)))) orelse .{ .out_of_bounds = {} };
                }
                if (target == .map and index == .string) {
                    return target.map.getVal(index) orelse .{ .none = {} };
                }
                return error.TypeError;
            },

            .call => |c| return try self.evalCall(c, scope),

            .struct_literal => |sl| {
                var field_names: std.ArrayListUnmanaged([]const u8) = .{};
                var field_values: std.ArrayListUnmanaged(Value) = .{};
                for (sl.fields) |field| {
                    try field_names.append(self.alloc, field.name);
                    try field_values.append(self.alloc, try self.evalExpr(field.value, scope));
                }
                return .{ .struct_val = .{
                    .name = sl.name,
                    .field_names = try field_names.toOwnedSlice(self.alloc),
                    .field_values = try field_values.toOwnedSlice(self.alloc),
                } };
            },
            .match_expr => return .{ .void = {} },
        }
    }

    fn evalBinaryOp(self: *Interpreter, op: ast.BinaryOp, scope: *Scope) Error!Value {
        const left = try self.evalExpr(op.left.*, scope);
        const right = try self.evalExpr(op.right.*, scope);

        // Poison propagation
        if (left.isPoison()) return left;
        if (right.isPoison()) return right;

        switch (op.op) {
            .add => {
                if (left == .int and right == .int) {
                    const result = @addWithOverflow(left.int, right.int);
                    if (result[1] != 0) return .{ .overflow = {} };
                    return .{ .int = result[0] };
                }
                if (left == .float and right == .float) return .{ .float = left.float + right.float };
                if (left == .string and right == .string) {
                    const combined = try std.mem.concat(self.alloc, u8, &.{ left.string, right.string });
                    return .{ .string = combined };
                }
                return error.TypeError;
            },
            .sub => {
                if (left == .int and right == .int) {
                    const result = @subWithOverflow(left.int, right.int);
                    if (result[1] != 0) return .{ .overflow = {} };
                    return .{ .int = result[0] };
                }
                if (left == .float and right == .float) return .{ .float = left.float - right.float };
                return error.TypeError;
            },
            .mul => {
                if (left == .int and right == .int) {
                    const result = @mulWithOverflow(left.int, right.int);
                    if (result[1] != 0) return .{ .overflow = {} };
                    return .{ .int = result[0] };
                }
                if (left == .float and right == .float) return .{ .float = left.float * right.float };
                return error.TypeError;
            },
            .div => {
                if (left == .int and right == .int) {
                    if (right.int == 0) return .{ .div_zero = {} };
                    return .{ .int = @divTrunc(left.int, right.int) };
                }
                if (left == .float and right == .float) {
                    if (right.float == 0.0) return .{ .infinity = {} };
                    return .{ .float = left.float / right.float };
                }
                return error.TypeError;
            },
            .mod => {
                if (left == .int and right == .int) {
                    if (right.int == 0) return .{ .div_zero = {} };
                    return .{ .int = @mod(left.int, right.int) };
                }
                return error.TypeError;
            },
            .eq => return .{ .bool = Value.eql(left, right) },
            .neq => return .{ .bool = !Value.eql(left, right) },
            .lt => {
                if (left == .int and right == .int) return .{ .bool = left.int < right.int };
                if (left == .float and right == .float) return .{ .bool = left.float < right.float };
                return error.TypeError;
            },
            .gt => {
                if (left == .int and right == .int) return .{ .bool = left.int > right.int };
                if (left == .float and right == .float) return .{ .bool = left.float > right.float };
                return error.TypeError;
            },
            .lte => {
                if (left == .int and right == .int) return .{ .bool = left.int <= right.int };
                if (left == .float and right == .float) return .{ .bool = left.float <= right.float };
                return error.TypeError;
            },
            .gte => {
                if (left == .int and right == .int) return .{ .bool = left.int >= right.int };
                if (left == .float and right == .float) return .{ .bool = left.float >= right.float };
                return error.TypeError;
            },
            .@"and" => return .{ .bool = left.isTruthy() and right.isTruthy() },
            .@"or" => return .{ .bool = left.isTruthy() or right.isTruthy() },
            .not => return error.TypeError,
        }
    }

    fn evalUnaryOp(self: *Interpreter, op: ast.UnaryOp, scope: *Scope) Error!Value {
        const operand = try self.evalExpr(op.operand.*, scope);
        switch (op.op) {
            .not => {
                if (operand == .bool) return .{ .bool = !operand.bool };
                return error.TypeError;
            },
            .sub => {
                if (operand == .int) return .{ .int = -operand.int };
                if (operand == .float) return .{ .float = -operand.float };
                return error.TypeError;
            },
            else => return error.TypeError,
        }
    }

    fn evalCall(self: *Interpreter, call: ast.Call, scope: *Scope) Error!Value {
        // Evaluate arguments
        var args_buf: [64]Value = undefined;
        var arg_count: usize = 0;
        for (call.args) |arg_expr| {
            args_buf[arg_count] = try self.evalExpr(arg_expr, scope);
            arg_count += 1;
        }
        const args = args_buf[0..arg_count];

        // Module.function(args) or process.Handler(args) — field access call
        if (call.target.* == .field_access) {
            const fa = call.target.field_access;
            if (fa.target.* == .identifier) {
                const target_name = fa.target.identifier;
                const fn_name = fa.field;

                // Check for built-in modules
                if (std.mem.eql(u8, target_name, "String")) {
                    return try self.builtinString(fn_name, args);
                }

                // Check if target is a process variable in scope
                if (scope.get(target_name)) |target_val| {
                    if (target_val == .process_id) {
                        // This is process.Handler(args, timeout) — send pattern
                        // Last arg is timeout (for send), but we ignore it in interpreter
                        return try self.sendToProcess(target_val.process_id, fn_name, args);
                    }
                }

                // Check if target is a known process name (for direct process.Handler calls)
                if (self.scheduler.getProcessByName(target_name)) |target_proc| {
                    return try self.sendToProcess(target_proc.id, fn_name, args);
                }

                return try self.callFunction(target_name, fn_name, args);
            }
        }

        // Direct function call: func(args) — look up in scope or builtins
        if (call.target.* == .identifier) {
            const name = call.target.identifier;

            // Built-in functions
            if (std.mem.eql(u8, name, "print")) {
                return self.builtinPrint(args);
            }
            if (std.mem.eql(u8, name, "println")) {
                return self.builtinPrintln(args);
            }
            if (std.mem.eql(u8, name, "list")) {
                // list() — create empty mutable list
                const ml = try self.alloc.create(Value.MutableList);
                ml.* = Value.MutableList.init(self.alloc);
                return .{ .list = ml };
            }
            if (std.mem.eql(u8, name, "spawn")) {
                // spawn expects first arg to be a process name (identifier)
                // In practice: p = spawn Ledger(); — parsed as call to spawn with Ledger as arg
                // For now, handle spawn("ProcessName")
                if (args.len > 0 and args[0] == .string) {
                    return try self.spawnProcess(args[0].string);
                }
                return error.TypeError;
            }

            // Check if it's a function in scope
            if (scope.get(name)) |val| {
                if (val == .function_ref) {
                    return try self.callFunction(val.function_ref.module_name, val.function_ref.fn_name, args);
                }
            }
            // Check if it's a function in any loaded module (single-module shorthand)
            var mod_iter = self.modules.iterator();
            while (mod_iter.next()) |entry| {
                for (entry.value_ptr.functions) |func| {
                    if (std.mem.eql(u8, func.name, name)) {
                        return try self.execFunction(func, args);
                    }
                }
            }
            return error.UndefinedFunction;
        }

        return error.UndefinedFunction;
    }

    // ── Built-in String module ────────────────────────────────

    fn builtinString(self: *Interpreter, fn_name: []const u8, args: []const Value) Error!Value {
        _ = self;
        if (std.mem.eql(u8, fn_name, "len")) {
            if (args.len > 0 and args[0] == .string) {
                return .{ .int = @intCast(args[0].string.len) };
            }
        }
        if (std.mem.eql(u8, fn_name, "contains")) {
            if (args.len >= 2 and args[0] == .string and args[1] == .string) {
                return .{ .bool = std.mem.indexOf(u8, args[0].string, args[1].string) != null };
            }
        }
        return error.UndefinedFunction;
    }

    // ── Built-in print ─────────────────────────────────────────

    fn builtinPrint(self: *Interpreter, args: []const Value) Value {
        _ = self;
        for (args) |arg| {
            printValueToStdout(arg);
        }
        return .{ .void = {} };
    }

    fn builtinPrintln(self: *Interpreter, args: []const Value) Value {
        _ = self;
        for (args) |arg| {
            printValueToStdout(arg);
        }
        std.debug.print("\n", .{});
        return .{ .void = {} };
    }

    fn printValueToStdout(val: Value) void {
        switch (val) {
            .int => |v| std.debug.print("{d}", .{v}),
            .float => |v| std.debug.print("{d}", .{v}),
            .string => |v| std.debug.print("{s}", .{v}),
            .bool => |v| std.debug.print("{}", .{v}),
            .tag => |v| std.debug.print(":{s}", .{v}),
            .tag_with_value => |v| {
                std.debug.print(":{s}{{", .{v.tag});
                for (v.values, 0..) |inner, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    printValueToStdout(inner);
                }
                std.debug.print("}}", .{});
            },
            .none => std.debug.print("none", .{}),
            .void => std.debug.print("void", .{}),
            .overflow => std.debug.print(":overflow", .{}),
            .div_zero => std.debug.print(":div_zero", .{}),
            .out_of_bounds => std.debug.print(":out_of_bounds", .{}),
            .nan => std.debug.print(":nan", .{}),
            .infinity => std.debug.print(":infinity", .{}),
            .list => |v| {
                std.debug.print("[", .{});
                for (v.items.items, 0..) |item, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    printValueToStdout(item);
                }
                std.debug.print("]", .{});
            },
            .process_id => |v| std.debug.print("process<{d}>", .{v}),
            else => std.debug.print("(...)", .{}),
        }
    }

    // ── Helpers ───────────────────────────────────────────────

    fn allocValues(self: *Interpreter, values: []const Value) Error![]Value {
        const slice = try self.alloc.alloc(Value, values.len);
        @memcpy(slice, values);
        return slice;
    }
};

// ── Scope ─────────────────────────────────────────────────

pub const Scope = struct {
    vars: std.StringHashMapUnmanaged(Value),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Scope {
        return .{
            .vars = .{},
            .alloc = alloc,
        };
    }

    pub fn get(self: *Scope, name: []const u8) ?Value {
        return self.vars.get(name);
    }

    pub fn set(self: *Scope, name: []const u8, value: Value) !void {
        try self.vars.put(self.alloc, name, value);
    }
};
