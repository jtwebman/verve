const std = @import("std");
const ir = @import("ir.zig");
const x86 = @import("x86.zig");
const elf = @import("elf.zig");

/// Linux x86_64 backend.
/// Consumes target-independent IR, emits x86_64 machine code + ELF binary.
/// Maps IR builtins to Linux syscalls.

pub const LinuxX86Backend = struct {
    alloc: std.mem.Allocator,
    asm_: x86.Asm,
    rodata: std.ArrayListUnmanaged(u8),
    // Virtual register → stack offset mapping
    reg_offsets: std.AutoHashMapUnmanaged(ir.Reg, i32),
    // Local variable name → stack offset
    local_offsets: std.StringHashMapUnmanaged(i32),
    next_stack_offset: i32,
    // Block ID → code offset for patching jumps
    block_offsets: std.AutoHashMapUnmanaged(ir.BlockId, usize),
    // Pending jump patches: (code_offset_of_rel32, target_block_id)
    jump_patches: std.ArrayListUnmanaged(JumpPatch),
    // Is this the entry point (main)?
    is_entry: bool,
    // Rodata address patches: code offsets where rodata offsets need to be fixed up
    rodata_patches: std.ArrayListUnmanaged(usize),
    // Function name → code offset for call patching
    fn_offsets: std.StringHashMapUnmanaged(usize),
    // Pending function call patches
    fn_call_patches: std.ArrayListUnmanaged(FnCallPatch),

    const FnCallPatch = struct {
        patch_offset: usize,
        target: []const u8, // "Module.function"
    };

    const JumpPatch = struct {
        patch_offset: usize,
        target_block: ir.BlockId,
    };

    pub fn init(alloc: std.mem.Allocator) LinuxX86Backend {
        return .{
            .alloc = alloc,
            .asm_ = x86.Asm.init(alloc),
            .rodata = .{},
            .reg_offsets = .{},
            .local_offsets = .{},
            .next_stack_offset = -8,
            .block_offsets = .{},
            .jump_patches = .{},
            .is_entry = false,
            .fn_offsets = .{},
            .fn_call_patches = .{},
            .rodata_patches = .{},
        };
    }

    fn addString(self: *LinuxX86Backend, s: []const u8) u32 {
        const offset: u32 = @intCast(self.rodata.items.len);
        self.rodata.appendSlice(self.alloc, s) catch {};
        return offset;
    }

    /// Get or allocate a stack slot for a virtual register.
    fn regSlot(self: *LinuxX86Backend, reg: ir.Reg) i32 {
        if (self.reg_offsets.get(reg)) |offset| return offset;
        const offset = self.next_stack_offset;
        self.reg_offsets.put(self.alloc, reg, offset) catch {};
        self.next_stack_offset -= 8;
        return offset;
    }

    /// Get or allocate a stack slot for a named local variable.
    fn localSlot(self: *LinuxX86Backend, name: []const u8) i32 {
        if (self.local_offsets.get(name)) |offset| return offset;
        const offset = self.next_stack_offset;
        self.local_offsets.put(self.alloc, name, offset) catch {};
        self.next_stack_offset -= 8;
        return offset;
    }

    /// Store rax into the stack slot for a virtual register.
    fn storeReg(self: *LinuxX86Backend, reg: ir.Reg) void {
        const offset = self.regSlot(reg);
        self.asm_.storeLocal32(offset, .rax);
    }

    /// Load a virtual register from its stack slot into rax.
    fn loadReg(self: *LinuxX86Backend, reg: ir.Reg) void {
        const offset = self.regSlot(reg);
        self.asm_.loadLocal32(.rax, offset);
    }

    // ── Compile program ──────────────────────────────────────

    pub fn compileProgram(self: *LinuxX86Backend, program: ir.Program) void {
        // Compile entry point first (must be at start of code)
        for (program.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "main")) {
                const key = std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ func.module, func.name }) catch "";
                self.fn_offsets.put(self.alloc, key, self.asm_.offset()) catch {};
                self.compileFunction(func, true);
            }
        }
        // Then compile all other functions
        for (program.functions.items) |func| {
            if (!std.mem.eql(u8, func.name, "main")) {
                const key = std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ func.module, func.name }) catch "";
                self.fn_offsets.put(self.alloc, key, self.asm_.offset()) catch {};
                self.compileFunction(func, false);
            }
        }
        // Patch all function calls
        for (self.fn_call_patches.items) |patch| {
            if (self.fn_offsets.get(patch.target)) |target_offset| {
                self.asm_.patchRel32At(patch.patch_offset, target_offset);
            }
        }
    }

    fn compileFunction(self: *LinuxX86Backend, func: ir.Function, is_entry: bool) void {
        // Reset per-function state
        self.reg_offsets = .{};
        self.local_offsets = .{};
        self.next_stack_offset = -8;
        self.block_offsets = .{};
        self.jump_patches = .{};
        self.is_entry = is_entry;

        // Prologue
        self.asm_.pushReg(.rbp);
        self.asm_.movReg(.rbp, .rsp);
        self.asm_.subImm32(.rsp, 4096); // reserve 4KB for locals

        // Store incoming arguments (System V ABI: rdi, rsi, rdx, rcx, r8, r9)
        const arg_regs = [_]x86.Reg64{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
        for (func.params, 0..) |param, i| {
            if (i < arg_regs.len) {
                const offset = self.localSlot(param.name);
                self.asm_.storeLocal32(offset, arg_regs[i]);
            }
        }

        // Compile each block
        for (func.blocks.items) |block| {
            // Record block start offset for jump patching
            self.block_offsets.put(self.alloc, block.id, self.asm_.offset()) catch {};

            for (block.insts.items) |inst| {
                self.compileInst(inst);
            }
        }

        // Default epilogue (if no explicit return was emitted)
        if (!is_entry) {
            self.asm_.movImm64(.rax, 0);
            self.asm_.movReg(.rsp, .rbp);
            self.asm_.popReg(.rbp);
            self.asm_.ret();
        } else {
            // Entry: default exit(0)
            self.asm_.movImm64(.rdi, 0);
            self.emitSyscall(60);
        }

        // Patch all jumps
        for (self.jump_patches.items) |patch| {
            if (self.block_offsets.get(patch.target_block)) |target_offset| {
                self.asm_.patchRel32At(patch.patch_offset, target_offset);
            }
        }
    }

    // ── Compile instruction ──────────────────────────────────

    fn compileInst(self: *LinuxX86Backend, inst: ir.Inst) void {
        switch (inst) {
            // ── Constants
            .const_int => |c| {
                self.asm_.movImm64(.rax, c.value);
                self.storeReg(c.dest);
            },
            .const_bool => |c| {
                self.asm_.movImm64(.rax, if (c.value) 1 else 0);
                self.storeReg(c.dest);
            },
            .const_string => |c| {
                const offset = self.addString(c.value);
                self.emitRodataAddr(.rax, offset);
                self.storeReg(c.dest);
            },
            .const_float => |c| {
                _ = c; // TODO: float support
            },

            // ── Arithmetic
            .add_i64 => |op| { self.compileBinOp(op, .add); },
            .sub_i64 => |op| { self.compileBinOp(op, .sub); },
            .mul_i64 => |op| { self.compileBinOp(op, .mul); },
            .div_i64 => |op| { self.compileBinOp(op, .div); },
            .mod_i64 => |op| { self.compileBinOp(op, .mod); },
            .neg_i64 => |op| {
                self.loadReg(op.operand);
                self.asm_.negReg(.rax);
                self.storeReg(op.dest);
            },

            // ── Comparison
            .eq_i64 => |op| { self.compileCmp(op, .eq); },
            .neq_i64 => |op| { self.compileCmp(op, .neq); },
            .lt_i64 => |op| { self.compileCmp(op, .lt); },
            .gt_i64 => |op| { self.compileCmp(op, .gt); },
            .lte_i64 => |op| { self.compileCmp(op, .lte); },
            .gte_i64 => |op| { self.compileCmp(op, .gte); },

            // ── Logical
            .and_bool => |op| { self.compileBinOp(op, .@"and"); },
            .or_bool => |op| { self.compileBinOp(op, .@"or"); },
            .not_bool => |op| {
                self.loadReg(op.operand);
                self.asm_.xorImm8(.rax, 1);
                self.storeReg(op.dest);
            },

            // ── Variables
            .store_local => |s| {
                self.loadReg(s.src);
                const offset = self.localSlot(s.name);
                self.asm_.storeLocal32(offset, .rax);
            },
            .load_local => |l| {
                const offset = self.localSlot(l.name);
                self.asm_.loadLocal32(.rax, offset);
                self.storeReg(l.dest);
            },

            // ── Control flow
            .jump => |j| {
                const patch = self.asm_.jmpRel32();
                self.jump_patches.append(self.alloc, .{
                    .patch_offset = patch,
                    .target_block = j.target,
                }) catch {};
            },
            .branch => |b| {
                self.loadReg(b.cond);
                self.asm_.testReg(.rax);
                // je else_block (jump if zero = false)
                const else_patch = self.asm_.jeRel32();
                // fall through to then_block
                const then_patch = self.asm_.jmpRel32();
                self.jump_patches.append(self.alloc, .{
                    .patch_offset = then_patch,
                    .target_block = b.then_block,
                }) catch {};
                self.jump_patches.append(self.alloc, .{
                    .patch_offset = else_patch,
                    .target_block = b.else_block,
                }) catch {};
            },
            .ret => |r| {
                if (r.value) |reg| {
                    self.loadReg(reg);
                } else {
                    self.asm_.movImm64(.rax, 0);
                }
                if (self.is_entry) {
                    // In main: exit syscall
                    self.asm_.movReg(.rdi, .rax);
                    self.emitSyscall(60); // sys_exit
                } else {
                    // Normal return
                    self.asm_.movReg(.rsp, .rbp);
                    self.asm_.popReg(.rbp);
                    self.asm_.ret();
                }
            },

            // ── Calls
            .call_builtin => |c| {
                self.compileBuiltin(c.dest, c.name, c.args);
            },
            .call => |c| {
                // System V AMD64 calling convention: rdi, rsi, rdx, rcx, r8, r9
                const arg_regs = [_]x86.Reg64{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };

                // Load args into calling convention registers
                for (c.args, 0..) |arg_reg, i| {
                    if (i < arg_regs.len) {
                        self.loadReg(arg_reg);
                        self.asm_.movReg(arg_regs[i], .rax);
                    }
                }

                // Emit call (will be patched later)
                const key = std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ c.module, c.function }) catch "";
                const patch = self.asm_.callRel32();
                self.fn_call_patches.append(self.alloc, .{
                    .patch_offset = patch,
                    .target = key,
                }) catch {};

                // Result is in rax
                self.storeReg(c.dest);
            },
        }
    }

    const ArithOp = enum { add, sub, mul, div, mod, @"and", @"or" };

    fn compileBinOp(self: *LinuxX86Backend, op: ir.Inst.BinOp, arith: ArithOp) void {
        self.loadReg(op.lhs);
        self.asm_.pushReg(.rax);
        self.loadReg(op.rhs);
        self.asm_.movReg(.rcx, .rax);
        self.asm_.popReg(.rax);

        switch (arith) {
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
                self.asm_.movReg(.rax, .rdx);
            },
            .@"and" => self.asm_.andReg(.rax, .rcx),
            .@"or" => self.asm_.orReg(.rax, .rcx),
        }
        self.storeReg(op.dest);
    }

    const CmpKind = enum { eq, neq, lt, gt, lte, gte };

    fn compileCmp(self: *LinuxX86Backend, op: ir.Inst.BinOp, kind: CmpKind) void {
        self.loadReg(op.lhs);
        self.asm_.pushReg(.rax);
        self.loadReg(op.rhs);
        self.asm_.movReg(.rcx, .rax);
        self.asm_.popReg(.rax);
        self.asm_.cmpReg(.rax, .rcx);

        switch (kind) {
            .eq => self.asm_.sete(.rax),
            .neq => self.asm_.setne(.rax),
            .lt => self.asm_.setl(.rax),
            .gt => self.asm_.setg(.rax),
            .lte => self.asm_.setle(.rax),
            .gte => self.asm_.setge(.rax),
        }
        self.asm_.movzxByte(.rax, .rax);
        self.storeReg(op.dest);
    }

    // ── Platform builtins (Linux syscalls) ────────────────────

    fn compileBuiltin(self: *LinuxX86Backend, dest: ir.Reg, name: []const u8, args: []const ir.Reg) void {
        if (std.mem.eql(u8, name, "println") or std.mem.eql(u8, name, "print")) {
            const newline = std.mem.eql(u8, name, "println");
            // Args come as (addr, len) pairs for string args
            var i: usize = 0;
            while (i + 1 < args.len) {
                // addr in args[i], len in args[i+1]
                self.loadReg(args[i]); // string rodata offset → rax
                self.asm_.movReg(.rsi, .rax); // buf
                self.loadReg(args[i + 1]); // length → rax
                self.asm_.movReg(.rdx, .rax); // len
                self.asm_.movImm64(.rdi, 1); // fd = stdout
                self.emitSyscall(1); // sys_write
                i += 2;
            }
            if (newline) {
                const nl_offset = self.addString("\n");
                self.emitRodataAddr(.rsi, nl_offset);
                self.asm_.movImm64(.rdx, 1);
                self.asm_.movImm64(.rdi, 1);
                self.emitSyscall(1);
            }
            self.asm_.movImm64(.rax, 0);
            self.storeReg(dest);
            return;
        }
        // Unknown builtin — no-op
        self.asm_.movImm64(.rax, 0);
        self.storeReg(dest);
    }

    /// Emit movImm64 with a rodata offset that will be patched to absolute address.
    fn emitRodataAddr(self: *LinuxX86Backend, dst: x86.Reg64, rodata_offset: u32) void {
        self.asm_.movImm64(dst, @intCast(rodata_offset));
        // Record the offset of the immediate value for patching
        self.rodata_patches.append(self.alloc, self.asm_.offset() - 8) catch {};
    }

    fn emitSyscall(self: *LinuxX86Backend, number: i64) void {
        self.asm_.movImm64(.rax, number);
        self.asm_.syscall();
    }

    // ── Build final binary ───────────────────────────────────

    pub fn build(self: *LinuxX86Backend, output_path: []const u8) !void {
        // Patch rodata addresses using tracked patch locations
        if (self.rodata.items.len > 0) {
            const layout = elf.computeLayout(self.asm_.code.items.len, self.rodata.items.len);
            for (self.rodata_patches.items) |patch_offset| {
                const val: u64 = @bitCast(self.asm_.code.items[patch_offset..][0..8].*);
                const new_val = val + layout.rodata_vaddr;
                const new_bytes: [8]u8 = @bitCast(new_val);
                @memcpy(self.asm_.code.items[patch_offset..][0..8], &new_bytes);
            }
        }
        try elf.emit(self.alloc, self.asm_.code.items, self.rodata.items, output_path);
    }
};
