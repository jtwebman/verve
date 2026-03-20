const std = @import("std");
const ast = @import("ast.zig");
const x86 = @import("x86.zig");
const elf = @import("elf.zig");

/// Compiles Verve AST directly to x86_64 machine code.
/// No dependencies in output. Uses Linux syscalls.

pub const Codegen = struct {
    alloc: std.mem.Allocator,
    asm_: x86.Asm,
    rodata: std.ArrayListUnmanaged(u8),
    // Local variables: name → stack offset (negative from rbp)
    locals: std.StringHashMapUnmanaged(i8),
    next_local: i8,

    pub fn init(alloc: std.mem.Allocator) Codegen {
        return .{
            .alloc = alloc,
            .asm_ = x86.Asm.init(alloc),
            .rodata = .{},
            .locals = .{},
            .next_local = -8,
        };
    }

    /// Add a string to rodata, return its offset.
    fn addString(self: *Codegen, s: []const u8) u32 {
        const offset: u32 = @intCast(self.rodata.items.len);
        self.rodata.appendSlice(self.alloc, s) catch {};
        return offset;
    }

    /// Allocate a stack slot for a local variable.
    fn allocLocal(self: *Codegen, name: []const u8) i8 {
        if (self.locals.get(name)) |offset| return offset;
        const offset = self.next_local;
        self.locals.put(self.alloc, name, offset) catch {};
        self.next_local -= 8;
        return offset;
    }

    // ── Top-level compilation ────────────────────────────────

    /// Compile a parsed file. Finds main() and emits it as the entry point.
    pub fn compile(self: *Codegen, file: ast.File) !void {
        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| {
                    for (m.functions) |func| {
                        if (std.mem.eql(u8, func.name, "main")) {
                            try self.compileMain(func);
                            return;
                        }
                    }
                },
                .process_decl => |p| {
                    for (p.receive_handlers) |handler| {
                        if (std.mem.eql(u8, handler.name, "main")) {
                            try self.compileMainHandler(handler);
                            return;
                        }
                    }
                },
                else => {},
            }
        }
    }

    fn compileMain(self: *Codegen, func: ast.FnDecl) !void {
        self.locals = .{};
        self.next_local = -8;

        // Prologue
        self.asm_.pushReg(.rbp);
        self.asm_.movReg(.rbp, .rsp);
        self.asm_.subRspImm8(128); // reserve stack space

        // Bind parameters (main gets args in rdi)
        for (func.params, 0..) |param, i| {
            const param_regs = [_]x86.Reg64{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
            if (i < param_regs.len) {
                const offset = self.allocLocal(param.name);
                self.asm_.storeLocal(offset, param_regs[i]);
            }
        }

        // Compile body
        for (func.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Default: exit(0)
        self.asm_.movImm64(.rdi, 0);
        self.asm_.movImm64(.rax, 60);
        self.asm_.syscall();
    }

    fn compileMainHandler(self: *Codegen, handler: ast.ReceiveDecl) !void {
        self.locals = .{};
        self.next_local = -8;

        self.asm_.pushReg(.rbp);
        self.asm_.movReg(.rbp, .rsp);
        self.asm_.subRspImm8(128);

        for (handler.params, 0..) |param, i| {
            const param_regs = [_]x86.Reg64{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
            if (i < param_regs.len) {
                const offset = self.allocLocal(param.name);
                self.asm_.storeLocal(offset, param_regs[i]);
            }
        }

        for (handler.body) |stmt| {
            try self.compileStmt(stmt);
        }

        self.asm_.movImm64(.rdi, 0);
        self.asm_.movImm64(.rax, 60);
        self.asm_.syscall();
    }

    // ── Statement compilation ────────────────────────────────

    fn compileStmt(self: *Codegen, stmt: ast.Stmt) !void {
        switch (stmt) {
            .return_stmt => |r| {
                if (r.value) |val| {
                    try self.compileExpr(val); // result in rax
                } else {
                    self.asm_.movImm64(.rax, 0);
                }
                // In main, return means exit
                self.asm_.movReg(.rdi, .rax);
                self.asm_.movImm64(.rax, 60); // sys_exit
                self.asm_.syscall();
            },
            .assign => |a| {
                try self.compileExpr(a.value); // result in rax
                const offset = self.allocLocal(a.name);
                self.asm_.storeLocal(offset, .rax);
            },
            .if_stmt => |i| {
                try self.compileExpr(i.condition);
                self.asm_.testReg(.rax);
                const else_patch = self.asm_.jeRel32();

                for (i.body) |s| try self.compileStmt(s);

                if (i.else_body) |eb| {
                    const end_patch = self.asm_.jmpRel32();
                    self.asm_.patchRel32(else_patch);
                    for (eb) |s| try self.compileStmt(s);
                    self.asm_.patchRel32(end_patch);
                } else {
                    self.asm_.patchRel32(else_patch);
                }
            },
            .while_stmt => |w| {
                const loop_top = self.asm_.offset();
                try self.compileExpr(w.condition);
                self.asm_.testReg(.rax);
                const exit_patch = self.asm_.jeRel32();

                for (w.body) |s| try self.compileStmt(s);

                // Jump back to loop top
                const jmp_patch = self.asm_.jmpRel32();
                self.asm_.patchRel32At(jmp_patch, loop_top);

                self.asm_.patchRel32(exit_patch);
            },
            .break_stmt => {
                // TODO: need a break target stack
            },
            .continue_stmt => {
                // TODO: need a continue target stack
            },
            .expr_stmt => |e| {
                try self.compileExpr(e);
            },
            else => {},
        }
    }

    // ── Expression compilation ───────────────────────────────
    // All expressions leave their result in rax.

    fn compileExpr(self: *Codegen, expr: ast.Expr) !void {
        switch (expr) {
            .int_literal => |v| {
                self.asm_.movImm64(.rax, v);
            },
            .bool_literal => |v| {
                self.asm_.movImm64(.rax, if (v) 1 else 0);
            },
            .string_literal => |v| {
                // Store string in rodata, load address into rax
                const offset = self.addString(v);
                // Address will be patched in build()
                self.asm_.movImm64(.rax, @intCast(offset));
            },
            .identifier => |name| {
                if (self.locals.get(name)) |offset| {
                    self.asm_.loadLocal(.rax, offset);
                }
            },
            .binary_op => |op| {
                // Left → rax, push, right → rax, pop left → rcx
                try self.compileExpr(op.left.*);
                self.asm_.pushReg(.rax);
                try self.compileExpr(op.right.*);
                self.asm_.movReg(.rcx, .rax); // right in rcx
                self.asm_.popReg(.rax); // left in rax

                switch (op.op) {
                    .add => self.asm_.addReg(.rax, .rcx),
                    .sub => self.asm_.subReg(.rax, .rcx),
                    .mul => self.asm_.imulReg(.rax, .rcx),
                    .div => {
                        self.asm_.cqo();
                        self.asm_.idivReg(.rcx);
                    },
                    .mod => {
                        self.asm_.cqo();
                        self.asm_.idivReg(.rcx);
                        self.asm_.movReg(.rax, .rdx); // remainder
                    },
                    .eq => {
                        self.asm_.cmpReg(.rax, .rcx);
                        self.asm_.sete(.rax);
                        self.asm_.movzxByte(.rax, .rax);
                    },
                    .neq => {
                        self.asm_.cmpReg(.rax, .rcx);
                        self.asm_.setne(.rax);
                        self.asm_.movzxByte(.rax, .rax);
                    },
                    .lt => {
                        self.asm_.cmpReg(.rax, .rcx);
                        self.asm_.setl(.rax);
                        self.asm_.movzxByte(.rax, .rax);
                    },
                    .gt => {
                        self.asm_.cmpReg(.rax, .rcx);
                        self.asm_.setg(.rax);
                        self.asm_.movzxByte(.rax, .rax);
                    },
                    .lte => {
                        self.asm_.cmpReg(.rax, .rcx);
                        self.asm_.setle(.rax);
                        self.asm_.movzxByte(.rax, .rax);
                    },
                    .gte => {
                        self.asm_.cmpReg(.rax, .rcx);
                        self.asm_.setge(.rax);
                        self.asm_.movzxByte(.rax, .rax);
                    },
                    .@"and" => self.asm_.andReg(.rax, .rcx),
                    .@"or" => self.asm_.orReg(.rax, .rcx),
                    .not => {},
                }
            },
            .unary_op => |op| {
                try self.compileExpr(op.operand.*);
                switch (op.op) {
                    .not => self.asm_.xorImm8(.rax, 1),
                    .sub => self.asm_.negReg(.rax),
                    else => {},
                }
            },
            else => {},
        }
    }

    // ── Build final binary ───────────────────────────────────

    pub fn build(self: *Codegen, output_path: []const u8) !void {
        // Patch string addresses: any movImm64 to rax that holds a rodata offset
        // needs to become rodata_vaddr + offset.
        // We track this by scanning for the pattern REX.W(48) B8 + small value
        if (self.rodata.items.len > 0) {
            const layout = elf.computeLayout(self.asm_.code.items.len, self.rodata.items.len);
            var i: usize = 0;
            while (i + 10 <= self.asm_.code.items.len) {
                // movImm64 rax: 48 B8 + imm64
                if (self.asm_.code.items[i] == 0x48 and self.asm_.code.items[i + 1] == 0xB8) {
                    const val: u64 = @bitCast(self.asm_.code.items[i + 2 ..][0..8].*);
                    if (val < self.rodata.items.len) {
                        const new_val = val + layout.rodata_vaddr;
                        const new_bytes: [8]u8 = @bitCast(new_val);
                        @memcpy(self.asm_.code.items[i + 2 ..][0..8], &new_bytes);
                    }
                    i += 10;
                    continue;
                }
                i += 1;
            }
        }

        try elf.emit(self.alloc, self.asm_.code.items, self.rodata.items, output_path);
    }
};
