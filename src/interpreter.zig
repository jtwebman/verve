const std = @import("std");
const ast = @import("ast.zig");
const Value = @import("value.zig").Value;
const proc = @import("process.zig");

pub const Interpreter = struct {
    alloc: std.mem.Allocator,
    modules: std.StringHashMapUnmanaged(ast.ModuleDecl),
    process_decls: std.StringHashMapUnmanaged(ast.ProcessDecl),
    module_constants: std.StringHashMapUnmanaged(std.StringHashMapUnmanaged(Value)),
    scheduler: proc.Scheduler,
    current_process: ?proc.ProcessId,
    current_module: ?[]const u8,
    source: ?[]const u8,
    runtime_error: ?RuntimeErrorInfo,

    pub const RuntimeErrorInfo = struct {
        message: []const u8,
        line: usize,
        col: usize,
    };

    pub const Error = error{
        RuntimeError,
        GuardFailed,
        ReturnValue,
        BreakSignal,
        ContinueSignal,
        AssertionFailed,
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
            .module_constants = .{},
            .scheduler = proc.Scheduler.init(alloc),
            .current_process = null,
            .current_module = null,
            .source = null,
            .runtime_error = null,
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
        // Initialize module-level constants
        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| try self.initModuleConstants(m),
                else => {},
            }
        }
    }

    fn initModuleConstants(self: *Interpreter, m: ast.ModuleDecl) Error!void {
        if (m.constants.len == 0) return;
        var consts: std.StringHashMapUnmanaged(Value) = .{};
        var scope = Scope.init(self.alloc);
        for (m.constants) |c| {
            const val = try self.evalExpr(c.value, &scope);
            // Freeze collections
            const frozen_val = freezeValue(val);
            try consts.put(self.alloc, c.name, frozen_val);
            try scope.set(c.name, frozen_val);
        }
        try self.module_constants.put(self.alloc, m.name, consts);
    }

    fn freezeValue(val: Value) Value {
        switch (val) {
            .list => |ml| { ml.frozen = true; return val; },
            .map => |mm| { mm.frozen = true; return val; },
            .set => |ms| { ms.frozen = true; return val; },
            .stack => |ms| { ms.frozen = true; return val; },
            .queue => |mq| { mq.frozen = true; return val; },
            else => return val,
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

        // Execute body (catch break/continue that leaked past while — runtime error)
        const result = self.execBlock(handler.body, &scope) catch |err| switch (err) {
            error.BreakSignal => return error.RuntimeError,
            error.ContinueSignal => return error.RuntimeError,
            else => return err,
        };
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
        const mod = self.modules.get(module_name) orelse {
            self.setRuntimeError("undefined module '{s}'", .{module_name}, .{ .start = 0, .end = 0 });
            return error.UndefinedModule;
        };

        const saved_module = self.current_module;
        self.current_module = module_name;
        defer self.current_module = saved_module;

        for (mod.functions) |func| {
            if (std.mem.eql(u8, func.name, fn_name)) {
                return try self.execFunction(func, args);
            }
        }

        self.setRuntimeError("undefined function '{s}.{s}'", .{ module_name, fn_name }, .{ .start = 0, .end = 0 });
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

        // Execute body (catch break/continue that leaked past while — runtime error)
        const result = self.execBlock(func.body, &scope) catch |err| switch (err) {
            error.BreakSignal => return error.RuntimeError,
            error.ContinueSignal => return error.RuntimeError,
            else => return err,
        };
        if (result.returned) return result.value;

        return result.value;
    }

    // ── Execute statements ────────────────────────────────────

    pub fn execBlock(self: *Interpreter, stmts: []const ast.Stmt, scope: *Scope) Error!Result {
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
            .break_stmt => return error.BreakSignal,
            .continue_stmt => return error.ContinueSignal,
            .if_stmt => |i| {
                const cond = try self.evalExpr(i.condition, scope);
                if (cond.isTruthy()) {
                    const result = try self.execBlock(i.body, scope);
                    if (result.returned) return result;
                } else if (i.else_body) |eb| {
                    const result = try self.execBlock(eb, scope);
                    if (result.returned) return result;
                }
                return .{ .value = .{ .void = {} }, .returned = false };
            },
            .while_stmt => |w| {
                while (true) {
                    const cond = try self.evalExpr(w.condition, scope);
                    if (!cond.isTruthy()) break;
                    const result = self.execBlock(w.body, scope) catch |err| switch (err) {
                        error.BreakSignal => break,
                        error.ContinueSignal => continue,
                        else => return err,
                    };
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
            .assert_stmt => |a| {
                const cond = try self.evalExpr(a.condition, scope);
                if (!cond.isTruthy()) {
                    if (a.message) |msg| {
                        self.setRuntimeError("assertion failed: {s}", .{msg}, a.span);
                    } else {
                        self.setRuntimeError("assertion failed", .{}, a.span);
                    }
                    return error.AssertionFailed;
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
                    .string_literal => |s| {
                        if (subject == .string) return std.mem.eql(u8, subject.string, s);
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
                // Check module-level constants
                if (self.current_module) |mod_name| {
                    if (self.module_constants.get(mod_name)) |consts| {
                        if (consts.get(name)) |v| return v;
                    }
                }
                // Check current process state
                if (self.current_process) |pid| {
                    if (self.scheduler.getProcess(pid)) |p| {
                        if (p.getState(name)) |v| return v;
                    }
                }
                self.setRuntimeError("undefined variable '{s}'", .{name}, .{ .start = 0, .end = 0 });
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
                    if (target == .set) return .{ .int = @intCast(target.set.len()) };
                    if (target == .stack) return .{ .int = @intCast(target.stack.len()) };
                    if (target == .queue) return .{ .int = @intCast(target.queue.len()) };
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
                if (target == .string and index == .int) {
                    const s = target.string;
                    const idx = index.int;
                    if (idx < 0 or idx >= @as(i64, @intCast(s.len))) return .{ .out_of_bounds = {} };
                    const i: usize = @intCast(@as(u64, @intCast(idx)));
                    return .{ .string = s[i .. i + 1] };
                }
                if (target == .map and index == .string) {
                    return target.map.getVal(index) orelse .{ .none = {} };
                }
                return error.TypeError;
            },

            .call => |c| return try self.evalCall(c, scope),

            .string_interp => |si| {
                var buf: std.ArrayListUnmanaged(u8) = .{};
                for (si.parts) |part| {
                    switch (part) {
                        .literal => |lit| buf.appendSlice(self.alloc, lit) catch return error.OutOfMemory,
                        .expr => |e| {
                            const val = try self.evalExpr(e, scope);
                            self.formatValueToBuffer(&buf, val) catch return error.OutOfMemory;
                        },
                    }
                }
                return .{ .string = buf.items };
            },
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

    fn typeNameOf(val: Value) []const u8 {
        return switch (val) {
            .int => "int",
            .float => "float",
            .bool => "bool",
            .string => "string",
            .tag => "tag",
            .tag_with_value => "tag",
            .none => "none",
            .void => "void",
            .list => "list",
            .map => "map",
            .set => "set",
            .stack => "stack",
            .queue => "queue",
            .stream => "stream",
            .struct_val => "struct",
            .function_ref => "function",
            .process_id => "process",
            .overflow, .div_zero, .out_of_bounds, .nan, .infinity => "poison",
        };
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
                self.setRuntimeError("cannot add {s} and {s}", .{ typeNameOf(left), typeNameOf(right) }, .{ .start = 0, .end = 0 });
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
                if (std.mem.eql(u8, target_name, "Map")) {
                    return try self.builtinMap(fn_name, args);
                }
                if (std.mem.eql(u8, target_name, "Set")) {
                    return try self.builtinSet(fn_name, args);
                }
                if (std.mem.eql(u8, target_name, "Queue")) {
                    return try self.builtinQueue(fn_name, args);
                }
                if (std.mem.eql(u8, target_name, "Stack")) {
                    return try self.builtinStack(fn_name, args);
                }
                if (std.mem.eql(u8, target_name, "Stdio")) {
                    return try self.builtinStdio(fn_name, args);
                }
                if (std.mem.eql(u8, target_name, "File")) {
                    return try self.builtinFile(fn_name, args);
                }
                if (std.mem.eql(u8, target_name, "Stream")) {
                    return try self.builtinStream(fn_name, args);
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
                // list(values...) — create list with optional initial values
                const ml = try self.alloc.create(Value.MutableList);
                ml.* = Value.MutableList.init(self.alloc);
                for (args) |arg| {
                    ml.append(arg) catch return error.OutOfMemory;
                }
                return .{ .list = ml };
            }
            if (std.mem.eql(u8, name, "map")) {
                // map(k1, v1, k2, v2, ...) — create map with optional initial key-value pairs
                const mm = try self.alloc.create(Value.MutableMap);
                mm.* = Value.MutableMap.init(self.alloc);
                var i: usize = 0;
                while (i + 1 < args.len) {
                    mm.put(args[i], args[i + 1]) catch return error.OutOfMemory;
                    i += 2;
                }
                return .{ .map = mm };
            }
            if (std.mem.eql(u8, name, "set")) {
                // set(values...) — create set with optional initial values
                const ms = try self.alloc.create(Value.MutableSet);
                ms.* = Value.MutableSet.init(self.alloc);
                for (args) |arg| {
                    ms.add(arg) catch return error.OutOfMemory;
                }
                return .{ .set = ms };
            }
            if (std.mem.eql(u8, name, "stack")) {
                const ms = try self.alloc.create(Value.MutableStack);
                ms.* = Value.MutableStack.init(self.alloc);
                for (args) |arg| {
                    ms.push(arg) catch return error.OutOfMemory;
                }
                return .{ .stack = ms };
            }
            if (std.mem.eql(u8, name, "queue")) {
                const mq = try self.alloc.create(Value.MutableQueue);
                mq.* = Value.MutableQueue.init(self.alloc);
                for (args) |arg| {
                    mq.push(arg) catch return error.OutOfMemory;
                }
                return .{ .queue = mq };
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
        if (std.mem.eql(u8, fn_name, "starts_with")) {
            if (args.len >= 2 and args[0] == .string and args[1] == .string) {
                return .{ .bool = std.mem.startsWith(u8, args[0].string, args[1].string) };
            }
        }
        if (std.mem.eql(u8, fn_name, "ends_with")) {
            if (args.len >= 2 and args[0] == .string and args[1] == .string) {
                return .{ .bool = std.mem.endsWith(u8, args[0].string, args[1].string) };
            }
        }
        if (std.mem.eql(u8, fn_name, "trim")) {
            if (args.len > 0 and args[0] == .string) {
                return .{ .string = std.mem.trim(u8, args[0].string, &[_]u8{ ' ', '\t', '\n', '\r' }) };
            }
        }
        if (std.mem.eql(u8, fn_name, "replace")) {
            if (args.len >= 3 and args[0] == .string and args[1] == .string and args[2] == .string) {
                const result = std.mem.replaceOwned(u8, self.alloc, args[0].string, args[1].string, args[2].string) catch return error.OutOfMemory;
                return .{ .string = result };
            }
        }
        if (std.mem.eql(u8, fn_name, "split")) {
            if (args.len >= 2 and args[0] == .string and args[1] == .string) {
                const ml = try self.alloc.create(Value.MutableList);
                ml.* = Value.MutableList.init(self.alloc);
                // Split by delimiter (first char of separator string)
                if (args[1].string.len > 0) {
                    var iter = std.mem.splitSequence(u8, args[0].string, args[1].string);
                    while (iter.next()) |part| {
                        ml.append(.{ .string = part }) catch return error.OutOfMemory;
                    }
                } else {
                    ml.append(.{ .string = args[0].string }) catch return error.OutOfMemory;
                }
                return .{ .list = ml };
            }
        }
        if (std.mem.eql(u8, fn_name, "byte_at")) {
            if (args.len >= 2 and args[0] == .string and args[1] == .int) {
                const s = args[0].string;
                const idx = args[1].int;
                if (idx < 0 or idx >= @as(i64, @intCast(s.len))) return .{ .out_of_bounds = {} };
                return .{ .int = @intCast(s[@intCast(@as(u64, @intCast(idx)))]) };
            }
        }
        if (std.mem.eql(u8, fn_name, "char_at")) {
            if (args.len >= 2 and args[0] == .string and args[1] == .int) {
                const s = args[0].string;
                const target_idx = args[1].int;
                if (target_idx < 0) return .{ .out_of_bounds = {} };
                // Walk UTF-8 code points to find the target_idx-th one
                var cp_idx: i64 = 0;
                var byte_pos: usize = 0;
                while (byte_pos < s.len) {
                    if (cp_idx == target_idx) {
                        const cp_len = std.unicode.utf8ByteSequenceLength(s[byte_pos]) catch return .{ .out_of_bounds = {} };
                        if (byte_pos + cp_len > s.len) return .{ .out_of_bounds = {} };
                        return .{ .string = s[byte_pos .. byte_pos + cp_len] };
                    }
                    const cp_len = std.unicode.utf8ByteSequenceLength(s[byte_pos]) catch return .{ .out_of_bounds = {} };
                    byte_pos += cp_len;
                    cp_idx += 1;
                }
                return .{ .out_of_bounds = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "char_len")) {
            if (args.len > 0 and args[0] == .string) {
                const s = args[0].string;
                var count: i64 = 0;
                var byte_pos: usize = 0;
                while (byte_pos < s.len) {
                    const cp_len = std.unicode.utf8ByteSequenceLength(s[byte_pos]) catch break;
                    byte_pos += cp_len;
                    count += 1;
                }
                return .{ .int = count };
            }
        }
        if (std.mem.eql(u8, fn_name, "chars")) {
            if (args.len > 0 and args[0] == .string) {
                const s = args[0].string;
                const ml = try self.alloc.create(Value.MutableList);
                ml.* = Value.MutableList.init(self.alloc);
                var byte_pos: usize = 0;
                while (byte_pos < s.len) {
                    const cp_len = std.unicode.utf8ByteSequenceLength(s[byte_pos]) catch break;
                    if (byte_pos + cp_len > s.len) break;
                    ml.append(.{ .string = s[byte_pos .. byte_pos + cp_len] }) catch return error.OutOfMemory;
                    byte_pos += cp_len;
                }
                return .{ .list = ml };
            }
        }
        if (std.mem.eql(u8, fn_name, "is_alpha")) {
            if (args.len > 0 and args[0] == .string) {
                const s = args[0].string;
                if (s.len == 0) return .{ .bool = false };
                return .{ .bool = std.ascii.isAlphabetic(s[0]) };
            }
        }
        if (std.mem.eql(u8, fn_name, "is_digit")) {
            if (args.len > 0 and args[0] == .string) {
                const s = args[0].string;
                if (s.len == 0) return .{ .bool = false };
                return .{ .bool = std.ascii.isDigit(s[0]) };
            }
        }
        if (std.mem.eql(u8, fn_name, "is_whitespace")) {
            if (args.len > 0 and args[0] == .string) {
                const s = args[0].string;
                if (s.len == 0) return .{ .bool = false };
                return .{ .bool = s[0] == ' ' or s[0] == '\t' or s[0] == '\n' or s[0] == '\r' };
            }
        }
        if (std.mem.eql(u8, fn_name, "is_alnum")) {
            if (args.len > 0 and args[0] == .string) {
                const s = args[0].string;
                if (s.len == 0) return .{ .bool = false };
                return .{ .bool = std.ascii.isAlphanumeric(s[0]) };
            }
        }
        if (std.mem.eql(u8, fn_name, "slice")) {
            if (args.len >= 3 and args[0] == .string and args[1] == .int and args[2] == .int) {
                const s = args[0].string;
                const start_raw = args[1].int;
                const end_raw = args[2].int;
                if (start_raw < 0 or end_raw < 0) return .{ .out_of_bounds = {} };
                const start: usize = @intCast(start_raw);
                const end: usize = @intCast(end_raw);
                if (start > s.len or end > s.len or start > end) return .{ .out_of_bounds = {} };
                return .{ .string = s[start..end] };
            }
        }
        return error.UndefinedFunction;
    }

    // ── Built-in Map module ─────────────────────────────────────

    fn builtinMap(self: *Interpreter, fn_name: []const u8, args: []const Value) Error!Value {
        if (std.mem.eql(u8, fn_name, "put")) {
            if (args.len >= 3 and args[0] == .map) {
                args[0].map.put(args[1], args[2]) catch return error.OutOfMemory;
                return .{ .void = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "get")) {
            if (args.len >= 2 and args[0] == .map) {
                return args[0].map.getVal(args[1]) orelse .{ .none = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "has")) {
            if (args.len >= 2 and args[0] == .map) {
                return .{ .bool = args[0].map.getVal(args[1]) != null };
            }
        }
        if (std.mem.eql(u8, fn_name, "keys")) {
            if (args.len >= 1 and args[0] == .map) {
                const ml = self.alloc.create(Value.MutableList) catch return error.OutOfMemory;
                ml.* = Value.MutableList.init(self.alloc);
                for (args[0].map.keys.items) |key| {
                    ml.append(key) catch return error.OutOfMemory;
                }
                return .{ .list = ml };
            }
        }
        return error.UndefinedFunction;
    }

    // ── Built-in Set module ──────────────────────────────────────

    fn builtinSet(self: *Interpreter, fn_name: []const u8, args: []const Value) Error!Value {
        if (std.mem.eql(u8, fn_name, "add")) {
            if (args.len >= 2 and args[0] == .set) {
                args[0].set.add(args[1]) catch return error.OutOfMemory;
                return .{ .void = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "has")) {
            if (args.len >= 2 and args[0] == .set) {
                return .{ .bool = args[0].set.has(args[1]) };
            }
        }
        if (std.mem.eql(u8, fn_name, "remove")) {
            if (args.len >= 2 and args[0] == .set) {
                args[0].set.remove(args[1]);
                return .{ .void = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "values")) {
            if (args.len >= 1 and args[0] == .set) {
                const ml = self.alloc.create(Value.MutableList) catch return error.OutOfMemory;
                ml.* = Value.MutableList.init(self.alloc);
                for (args[0].set.items.items) |item| {
                    ml.append(item) catch return error.OutOfMemory;
                }
                return .{ .list = ml };
            }
        }
        return error.UndefinedFunction;
    }

    // ── Built-in Stack module ─────────────────────────────────

    fn builtinStack(self: *Interpreter, fn_name: []const u8, args: []const Value) Error!Value {
        _ = self;
        if (std.mem.eql(u8, fn_name, "push")) {
            if (args.len >= 2 and args[0] == .stack) {
                args[0].stack.push(args[1]) catch return error.OutOfMemory;
                return .{ .void = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "pop")) {
            if (args.len >= 1 and args[0] == .stack) {
                return args[0].stack.pop() orelse .{ .none = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "peek")) {
            if (args.len >= 1 and args[0] == .stack) {
                return args[0].stack.peek() orelse .{ .none = {} };
            }
        }
        return error.UndefinedFunction;
    }

    // ── Built-in Queue module ─────────────────────────────────

    fn builtinQueue(self: *Interpreter, fn_name: []const u8, args: []const Value) Error!Value {
        _ = self;
        if (std.mem.eql(u8, fn_name, "push")) {
            if (args.len >= 2 and args[0] == .queue) {
                args[0].queue.push(args[1]) catch return error.OutOfMemory;
                return .{ .void = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "pop")) {
            if (args.len >= 1 and args[0] == .queue) {
                return args[0].queue.pop() orelse .{ .none = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "peek")) {
            if (args.len >= 1 and args[0] == .queue) {
                return args[0].queue.peek() orelse .{ .none = {} };
            }
        }
        return error.UndefinedFunction;
    }

    // ── Built-in Stdio module ─────────────────────────────────

    fn builtinStdio(self: *Interpreter, fn_name: []const u8, args: []const Value) Error!Value {
        _ = args;
        if (std.mem.eql(u8, fn_name, "out")) {
            const s = self.alloc.create(Value.Stream) catch return error.OutOfMemory;
            s.* = Value.Stream.initStdout();
            return .{ .stream = s };
        }
        if (std.mem.eql(u8, fn_name, "err")) {
            const s = self.alloc.create(Value.Stream) catch return error.OutOfMemory;
            s.* = Value.Stream.initStderr();
            return .{ .stream = s };
        }
        if (std.mem.eql(u8, fn_name, "in")) {
            const s = self.alloc.create(Value.Stream) catch return error.OutOfMemory;
            s.* = Value.Stream.initStdin();
            return .{ .stream = s };
        }
        return error.UndefinedFunction;
    }

    // ── Built-in File module ─────────────────────────────────

    fn builtinFile(self: *Interpreter, fn_name: []const u8, args: []const Value) Error!Value {
        if (std.mem.eql(u8, fn_name, "open")) {
            if (args.len >= 2 and args[0] == .string and args[1] == .string) {
                const path = args[0].string;
                const mode = args[1].string;

                if (std.mem.eql(u8, mode, "r")) {
                    // Read mode: read entire file into memory
                    const content = std.fs.cwd().readFileAlloc(self.alloc, path, 10 * 1024 * 1024) catch {
                        return .{ .tag_with_value = .{
                            .tag = "error",
                            .values = try self.allocValues(&.{.{ .tag = "not_found" }}),
                        } };
                    };
                    const s = self.alloc.create(Value.Stream) catch return error.OutOfMemory;
                    s.* = Value.Stream.initFileRead(content);
                    return .{ .tag_with_value = .{
                        .tag = "ok",
                        .values = try self.allocValues(&.{.{ .stream = s }}),
                    } };
                }

                if (std.mem.eql(u8, mode, "w")) {
                    const s = self.alloc.create(Value.Stream) catch return error.OutOfMemory;
                    s.* = Value.Stream.initFileWrite(path, self.alloc);
                    return .{ .tag_with_value = .{
                        .tag = "ok",
                        .values = try self.allocValues(&.{.{ .stream = s }}),
                    } };
                }

                return .{ .tag_with_value = .{
                    .tag = "error",
                    .values = try self.allocValues(&.{.{ .tag = "invalid_mode" }}),
                } };
            }
        }
        return error.UndefinedFunction;
    }

    // ── Built-in Stream module ───────────────────────────────

    fn builtinStream(self: *Interpreter, fn_name: []const u8, args: []const Value) Error!Value {
        if (std.mem.eql(u8, fn_name, "write")) {
            if (args.len >= 2 and args[0] == .stream) {
                const s = args[0].stream;
                if (s.closed) return .{ .tag_with_value = .{
                    .tag = "error",
                    .values = try self.allocValues(&.{.{ .tag = "closed" }}),
                } };
                switch (s.kind) {
                    .stdout => self.writeValueToFile(std.fs.File.stdout(), args[1]),
                    .stderr => self.writeValueToFile(std.fs.File.stderr(), args[1]),
                    .file_write => |*fw| {
                        if (args[1] == .string) {
                            fw.buf.appendSlice(fw.alloc, args[1].string) catch return error.OutOfMemory;
                        }
                    },
                    else => return .{ .tag_with_value = .{
                        .tag = "error",
                        .values = try self.allocValues(&.{.{ .tag = "not_writable" }}),
                    } },
                }
                return .{ .void = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "write_line")) {
            if (args.len >= 2 and args[0] == .stream) {
                const s = args[0].stream;
                if (s.closed) return .{ .tag_with_value = .{
                    .tag = "error",
                    .values = try self.allocValues(&.{.{ .tag = "closed" }}),
                } };
                switch (s.kind) {
                    .stdout => {
                        self.writeValueToFile(std.fs.File.stdout(), args[1]);
                        std.fs.File.stdout().writeAll("\n") catch {};
                    },
                    .stderr => {
                        self.writeValueToFile(std.fs.File.stderr(), args[1]);
                        std.fs.File.stderr().writeAll("\n") catch {};
                    },
                    .file_write => |*fw| {
                        if (args[1] == .string) {
                            fw.buf.appendSlice(fw.alloc, args[1].string) catch return error.OutOfMemory;
                        }
                        fw.buf.append(fw.alloc, '\n') catch return error.OutOfMemory;
                    },
                    else => return .{ .tag_with_value = .{
                        .tag = "error",
                        .values = try self.allocValues(&.{.{ .tag = "not_writable" }}),
                    } },
                }
                return .{ .void = {} };
            }
        }
        if (std.mem.eql(u8, fn_name, "read_line")) {
            if (args.len >= 1 and args[0] == .stream) {
                const s = args[0].stream;
                if (s.closed) return .{ .tag = "eof" };
                switch (s.kind) {
                    .stdin => {
                        // Read stdin byte-by-byte until newline or EOF
                        var line_buf: std.ArrayListUnmanaged(u8) = .{};
                        const stdin_file = std.fs.File.stdin();
                        while (true) {
                            var byte: [1]u8 = undefined;
                            const n = stdin_file.read(&byte) catch return .{ .tag = "eof" };
                            if (n == 0) {
                                // EOF
                                if (line_buf.items.len == 0) return .{ .tag = "eof" };
                                break;
                            }
                            if (byte[0] == '\n') break;
                            if (byte[0] != '\r') {
                                line_buf.append(self.alloc, byte[0]) catch return error.OutOfMemory;
                            }
                        }
                        return .{ .string = line_buf.items };
                    },
                    .file_read => |*fr| {
                        if (fr.pos >= fr.content.len) return .{ .tag = "eof" };
                        // Find next newline
                        const remaining = fr.content[fr.pos..];
                        const nl_pos = std.mem.indexOfScalar(u8, remaining, '\n');
                        if (nl_pos) |nl| {
                            const line = remaining[0..nl];
                            fr.pos += nl + 1;
                            // Strip trailing \r
                            const trimmed = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
                            return .{ .string = trimmed };
                        }
                        // No newline — return rest of content
                        fr.pos = fr.content.len;
                        return .{ .string = remaining };
                    },
                    else => return .{ .tag_with_value = .{
                        .tag = "error",
                        .values = try self.allocValues(&.{.{ .tag = "not_readable" }}),
                    } },
                }
            }
        }
        if (std.mem.eql(u8, fn_name, "read_all")) {
            if (args.len >= 1 and args[0] == .stream) {
                const s = args[0].stream;
                if (s.closed) return .{ .tag = "eof" };
                switch (s.kind) {
                    .file_read => |*fr| {
                        if (fr.pos >= fr.content.len) return .{ .tag = "eof" };
                        const remaining = fr.content[fr.pos..];
                        fr.pos = fr.content.len;
                        return .{ .string = remaining };
                    },
                    .stdin => {
                        const content = std.fs.File.stdin().readToEndAlloc(self.alloc, 10 * 1024 * 1024) catch return .{ .tag = "eof" };
                        return .{ .string = content };
                    },
                    else => return .{ .tag_with_value = .{
                        .tag = "error",
                        .values = try self.allocValues(&.{.{ .tag = "not_readable" }}),
                    } },
                }
            }
        }
        if (std.mem.eql(u8, fn_name, "close")) {
            if (args.len >= 1 and args[0] == .stream) {
                const s = args[0].stream;
                if (!s.closed) {
                    // Flush file_write on close
                    switch (s.kind) {
                        .file_write => |fw| {
                            std.fs.cwd().writeFile(.{
                                .sub_path = fw.path,
                                .data = fw.buf.items,
                            }) catch {};
                        },
                        else => {},
                    }
                    s.closed = true;
                }
                return .{ .void = {} };
            }
        }
        return error.UndefinedFunction;
    }

    fn writeValueToFile(self: *Interpreter, file: std.fs.File, val: Value) void {
        _ = self;
        switch (val) {
            .int => |v| {
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return;
                file.writeAll(s) catch {};
            },
            .float => |v| {
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return;
                file.writeAll(s) catch {};
            },
            .string => |v| file.writeAll(v) catch {},
            .bool => |v| file.writeAll(if (v) "true" else "false") catch {},
            .tag => |v| {
                file.writeAll(":") catch {};
                file.writeAll(v) catch {};
            },
            .none => file.writeAll("none") catch {},
            .void => file.writeAll("void") catch {},
            else => file.writeAll("(...)") catch {},
        }
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
            .map => |v| {
                std.debug.print("map{{", .{});
                for (v.keys.items, 0..) |key, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    printValueToStdout(key);
                    std.debug.print(": ", .{});
                    printValueToStdout(v.values.items[i]);
                }
                std.debug.print("}}", .{});
            },
            .set => |v| {
                std.debug.print("set{{", .{});
                for (v.items.items, 0..) |item, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    printValueToStdout(item);
                }
                std.debug.print("}}", .{});
            },
            .stack => |v| {
                std.debug.print("stack[", .{});
                for (v.items.items, 0..) |item, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    printValueToStdout(item);
                }
                std.debug.print("]", .{});
            },
            .queue => |v| {
                std.debug.print("queue[", .{});
                for (v.items.items, 0..) |item, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    printValueToStdout(item);
                }
                std.debug.print("]", .{});
            },
            .stream => |v| {
                const kind_name: []const u8 = switch (v.kind) {
                    .stdout => "stdout",
                    .stderr => "stderr",
                    .stdin => "stdin",
                    .file_read => "file(r)",
                    .file_write => "file(w)",
                };
                std.debug.print("stream<{s}>", .{kind_name});
            },
            .process_id => |v| std.debug.print("process<{d}>", .{v}),
            else => std.debug.print("(...)", .{}),
        }
    }

    // ── Helpers ───────────────────────────────────────────────

    fn formatValueToBuffer(self: *Interpreter, buf: *std.ArrayListUnmanaged(u8), val: Value) !void {
        _ = self;
        switch (val) {
            .int => |v| {
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return;
                try buf.appendSlice(std.heap.page_allocator, s);
            },
            .float => |v| {
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return;
                try buf.appendSlice(std.heap.page_allocator, s);
            },
            .string => |v| try buf.appendSlice(std.heap.page_allocator, v),
            .bool => |v| try buf.appendSlice(std.heap.page_allocator, if (v) "true" else "false"),
            .tag => |v| {
                try buf.appendSlice(std.heap.page_allocator, ":");
                try buf.appendSlice(std.heap.page_allocator, v);
            },
            .none => try buf.appendSlice(std.heap.page_allocator, "none"),
            .void => try buf.appendSlice(std.heap.page_allocator, "void"),
            .overflow => try buf.appendSlice(std.heap.page_allocator, ":overflow"),
            .div_zero => try buf.appendSlice(std.heap.page_allocator, ":div_zero"),
            .out_of_bounds => try buf.appendSlice(std.heap.page_allocator, ":out_of_bounds"),
            else => try buf.appendSlice(std.heap.page_allocator, "(...)"),
        }
    }

    fn setRuntimeError(self: *Interpreter, comptime fmt: []const u8, fmt_args: anytype, span: ast.Span) void {
        const message = std.fmt.allocPrint(self.alloc, fmt, fmt_args) catch "runtime error";
        if (self.source) |src| {
            var line: usize = 1;
            var col: usize = 1;
            const pos = @min(span.start, src.len);
            for (src[0..pos]) |c| {
                if (c == '\n') {
                    line += 1;
                    col = 1;
                } else {
                    col += 1;
                }
            }
            self.runtime_error = .{ .message = message, .line = line, .col = col };
        } else {
            self.runtime_error = .{ .message = message, .line = 0, .col = 0 };
        }
    }

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
