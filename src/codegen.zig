const std = @import("std");
const ast = @import("ast.zig");
const x86 = @import("x86.zig");
const elf = @import("elf.zig");

/// Compiles Verve AST directly to x86_64 machine code.
/// No dependencies. Uses Linux syscalls for IO.

pub const Codegen = struct {
    alloc: std.mem.Allocator,
    asm_: x86.Asm,
    rodata: std.ArrayListUnmanaged(u8),
    // String constants: maps string content to offset in rodata
    string_offsets: std.StringHashMapUnmanaged(u32),
    // Local variables: maps name to stack offset (negative from rbp)
    locals: std.StringHashMapUnmanaged(i8),
    next_local_offset: i8,
    // Function offsets for patching calls
    fn_offsets: std.StringHashMapUnmanaged(usize),
    // Pending call patches: (patch_offset_in_code, "Module.function")
    call_patches: std.ArrayListUnmanaged(CallPatch),

    const CallPatch = struct {
        patch_offset: usize,
        target: []const u8,
    };

    pub fn init(alloc: std.mem.Allocator) Codegen {
        return .{
            .alloc = alloc,
            .asm_ = x86.Asm.init(alloc),
            .rodata = .{},
            .string_offsets = .{},
            .locals = .{},
            .next_local_offset = -8,
            .fn_offsets = .{},
            .call_patches = .{},
        };
    }

    /// Add a string to rodata, return its offset
    fn addString(self: *Codegen, s: []const u8) u32 {
        if (self.string_offsets.get(s)) |offset| return offset;
        const offset: u32 = @intCast(self.rodata.items.len);
        self.rodata.appendSlice(self.alloc, s) catch {};
        self.string_offsets.put(self.alloc, s, offset) catch {};
        return offset;
    }

    /// Emit the write syscall: write(fd, buf, len)
    /// fd in rdi, buf in rsi, len in rdx
    fn emitWrite(self: *Codegen, fd: i64, str_offset: u32, len: u64) void {
        // mov rax, 1 (sys_write)
        self.asm_.movImm64(.rax, 1);
        // mov rdi, fd
        self.asm_.movImm64(.rdi, fd);
        // mov rsi, rodata_addr + offset (will be patched)
        // For now, use a placeholder — we'll compute the actual address after layout
        self.asm_.movImm64(.rsi, @intCast(str_offset)); // placeholder, patched later
        // mov rdx, len
        self.asm_.movImm64(.rdx, @intCast(len));
        // syscall
        self.asm_.syscall();
    }

    /// Emit exit syscall: exit(code)
    /// code in rdi
    fn emitExit(self: *Codegen, code_reg: x86.Reg64) void {
        self.asm_.movImm64(.rax, 60); // sys_exit
        if (code_reg != .rdi) {
            self.asm_.movReg(.rdi, code_reg);
        }
        self.asm_.syscall();
    }

    /// Compile a file to machine code
    pub fn compile(self: *Codegen, file: ast.File) !void {
        // Find entry point
        var entry_module: ?[]const u8 = null;

        // First pass: compile all functions
        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| {
                    for (m.functions) |func| {
                        const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ m.name, func.name });
                        try self.fn_offsets.put(self.alloc, key, self.asm_.offset());

                        if (std.mem.eql(u8, func.name, "main")) {
                            entry_module = m.name;
                        }

                        try self.compileFunction(func, m.name);
                    }
                },
                else => {},
            }
        }

        // Patch all function calls
        for (self.call_patches.items) |patch| {
            if (self.fn_offsets.get(patch.target)) |target_offset| {
                self.asm_.patchRel32At(patch.patch_offset, target_offset);
            }
        }
    }

    fn compileFunction(self: *Codegen, func: ast.FnDecl, module_name: []const u8) !void {
        _ = module_name;

        // Reset locals for this function
        self.locals = .{};
        self.next_local_offset = -8;

        // Function prologue
        self.asm_.pushReg(.rbp);
        self.asm_.movReg(.rbp, .rsp);
        // Reserve stack space (we'll patch this later if needed)
        self.asm_.subRspImm8(64); // reserve 64 bytes for locals

        // Bind parameters to stack slots
        const param_regs = [_]x86.Reg64{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
        for (func.params, 0..) |param, i| {
            if (i < param_regs.len) {
                const offset = self.allocLocal(param.name);
                self.asm_.storeLocal(offset, param_regs[i]);
            }
        }

        // Compile body
        for (func.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Default return 0 if no explicit return
        self.asm_.movImm64(.rax, 0);

        // Function epilogue
        self.asm_.movReg(.rsp, .rbp);
        self.asm_.popReg(.rbp);

        // If this is main, emit exit syscall instead of ret
        if (std.mem.eql(u8, func.name, "main")) {
            self.emitExit(.rax);
        } else {
            self.asm_.ret();
        }
    }

    fn allocLocal(self: *Codegen, name: []const u8) i8 {
        if (self.locals.get(name)) |offset| return offset;
        const offset = self.next_local_offset;
        self.locals.put(self.alloc, name, offset) catch {};
        self.next_local_offset -= 8;
        return offset;
    }

    fn compileStmt(self: *Codegen, stmt: ast.Stmt) !void {
        switch (stmt) {
            .assign => |a| {
                try self.compileExpr(a.value); // result in rax
                const offset = self.allocLocal(a.name);
                self.asm_.storeLocal(offset, .rax);
            },
            .return_stmt => |r| {
                if (r.value) |val| {
                    try self.compileExpr(val); // result in rax
                }
                // Epilogue
                self.asm_.movReg(.rsp, .rbp);
                self.asm_.popReg(.rbp);
                self.asm_.ret();
            },
            .expr_stmt => |e| {
                try self.compileExpr(e); // result discarded
            },
            .if_stmt => |i| {
                try self.compileExpr(i.condition); // result in rax
                self.asm_.testReg(.rax);
                const else_patch = self.asm_.jeRel32(); // jump to else if zero

                // Then body
                for (i.body) |s| try self.compileStmt(s);

                if (i.else_body) |eb| {
                    const end_patch = self.asm_.jmpRel32(); // jump over else
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

                // Jump back to top
                const back_patch = self.asm_.jmpRel32();
                // Patch backward jump
                const back_target = loop_top;
                const back_from = self.asm_.offset();
                const rel: i32 = @intCast(@as(i64, @intCast(back_target)) - @as(i64, @intCast(back_from)));
                const bytes: [4]u8 = @bitCast(rel);
                self.asm_.code.items[back_from - 4] = bytes[0];
                self.asm_.code.items[back_from - 3] = bytes[1];
                self.asm_.code.items[back_from - 2] = bytes[2];
                self.asm_.code.items[back_from - 1] = bytes[3];
                _ = back_patch;

                self.asm_.patchRel32(exit_patch);
            },
            else => {}, // TODO: other statements
        }
    }

    fn compileExpr(self: *Codegen, expr: ast.Expr) !void {
        switch (expr) {
            .int_literal => |v| {
                self.asm_.movImm64(.rax, v);
            },
            .bool_literal => |v| {
                self.asm_.movImm64(.rax, if (v) 1 else 0);
            },
            .string_literal => |v| {
                const offset = self.addString(v);
                // Load address of string in rodata — placeholder, patched after layout
                self.asm_.movImm64(.rax, @intCast(offset));
            },
            .identifier => |name| {
                if (self.locals.get(name)) |offset| {
                    self.asm_.loadLocal(.rax, offset);
                }
            },
            .binary_op => |op| {
                // Compile left into rax, push, compile right into rax, pop left into rcx
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
                        // idiv rcx — but our idiv has a bug, use raw bytes
                        self.asm_.rex(true, .rax, .rcx);
                        self.asm_.emit(0xF7);
                        self.asm_.emit(0xC0 | (7 << 3) | @as(u8, x86.Reg64.rcx.low3())); // /7 = idiv
                    },
                    .mod => {
                        self.asm_.cqo();
                        self.asm_.rex(true, .rax, .rcx);
                        self.asm_.emit(0xF7);
                        self.asm_.emit(0xC0 | (7 << 3) | @as(u8, x86.Reg64.rcx.low3()));
                        self.asm_.movReg(.rax, .rdx); // remainder in rdx
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
                    .@"and" => {
                        // Both are bools (0 or 1), AND them
                        self.asm_.rex(true, .rax, .rcx);
                        self.asm_.emit(0x21); // AND r/m64, r64
                        self.asm_.modrm(.rcx, .rax);
                    },
                    .@"or" => {
                        self.asm_.rex(true, .rax, .rcx);
                        self.asm_.emit(0x09); // OR r/m64, r64
                        self.asm_.modrm(.rcx, .rax);
                    },
                    .not => {},
                }
            },
            .unary_op => |op| {
                try self.compileExpr(op.operand.*);
                switch (op.op) {
                    .not => {
                        // XOR with 1 to flip bool
                        self.asm_.rex(true, .rax, .rax);
                        self.asm_.emit(0x83); // XOR r/m64, imm8
                        self.asm_.emit(0xF0); // modrm: /6, rm=rax
                        self.asm_.emit(1);
                    },
                    .sub => {
                        self.asm_.negReg(.rax);
                    },
                    else => {},
                }
            },
            .call => |c| {
                // Handle println specially — use write syscall
                if (c.target.* == .identifier) {
                    const name = c.target.identifier;
                    if (std.mem.eql(u8, name, "println")) {
                        try self.compilePrintln(c.args);
                        return;
                    }
                }
                // General function call: evaluate args into registers
                const param_regs = [_]x86.Reg64{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
                for (c.args, 0..) |arg, i| {
                    if (i < param_regs.len) {
                        try self.compileExpr(arg);
                        if (param_regs[i] != .rax) {
                            self.asm_.movReg(param_regs[i], .rax);
                        }
                        // Save to stack to avoid clobbering
                        if (i + 1 < c.args.len) {
                            self.asm_.pushReg(param_regs[i]);
                        }
                    }
                }
                // Restore saved args
                var ri: usize = c.args.len - 1;
                while (ri > 0) : (ri -= 1) {
                    if (ri < param_regs.len) {
                        self.asm_.popReg(param_regs[ri - 1]);
                    }
                }
                // TODO: emit call to the function
                // For now just call rel32 with a patch
            },
            else => {},
        }
    }

    fn compilePrintln(self: *Codegen, args: []const ast.Expr) !void {
        // For each arg: if it's a string literal, write it directly
        // For int args, we'd need itoa — for now just handle strings
        for (args) |arg| {
            switch (arg) {
                .string_literal => |s| {
                    const offset = self.addString(s);
                    self.emitWrite(1, offset, @intCast(s.len));
                },
                .int_literal => |v| {
                    // Convert int to string in rodata
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch "?";
                    const offset = self.addString(s);
                    self.emitWrite(1, offset, @intCast(s.len));
                },
                .identifier => |name| {
                    // For now, just print the variable name as a placeholder
                    _ = name;
                    // TODO: runtime integer-to-string conversion
                },
                else => {},
            }
        }
        // Print newline
        const nl_offset = self.addString("\n");
        self.emitWrite(1, nl_offset, 1);
    }

    /// After compilation, patch string addresses to actual rodata vaddrs
    fn patchStringAddresses(self: *Codegen) void {
        const rodata_vaddr = elf.rodataVaddr(self.asm_.code.items);

        // Walk through code looking for movImm64 instructions that load string offsets
        // This is a simplified approach — in a real compiler we'd track these properly
        // For now, the emitWrite function loads string offsets into rsi
        // We need to patch those to rodata_vaddr + offset

        // Actually, let's just rebuild the code with correct addresses
        // by storing the write calls' rsi patch locations
        _ = rodata_vaddr;
    }

    /// Build the final binary
    pub fn build(self: *Codegen, output_path: []const u8) !void {
        // Patch string addresses: each emitWrite loads a string offset into rsi
        // We need to add rodata_vaddr to each offset
        const rodata_vaddr = elf.rodataVaddr(self.asm_.code.items);

        // Scan code for movImm64 to rsi (REX.W + B8+6) and add rodata_vaddr
        // rsi = register 6, so opcode is 0x48 0xBE (REX.W + B8+6)
        var i: usize = 0;
        while (i < self.asm_.code.items.len) {
            if (i + 10 <= self.asm_.code.items.len) {
                // movImm64 rsi: REX.W(0x48) + 0xBE + imm64
                if (self.asm_.code.items[i] == 0x48 and self.asm_.code.items[i + 1] == 0xBE) {
                    // Read current value
                    const val_bytes = self.asm_.code.items[i + 2 .. i + 10];
                    const current_val: u64 = @bitCast(val_bytes[0..8].*);
                    // Only patch if it looks like a rodata offset (small number)
                    if (current_val < 1024 * 1024) {
                        const new_val = current_val + rodata_vaddr;
                        const new_bytes: [8]u8 = @bitCast(new_val);
                        @memcpy(self.asm_.code.items[i + 2 .. i + 10], &new_bytes);
                    }
                    i += 10;
                    continue;
                }
            }
            i += 1;
        }

        try elf.emit(self.alloc, self.asm_.code.items, self.rodata.items, output_path);
    }
};
