const std = @import("std");
const ir = @import("ir.zig");
const x86 = @import("x86.zig");
const elf = @import("elf.zig");

/// Linux x86_64 backend.
/// Consumes target-independent IR, emits x86_64 machine code + ELF binary.
/// Maps IR builtins to Linux syscalls.

pub const LinuxX86Backend = struct {
    const JumpPatch = struct {
        patch_offset: usize,
        target_block: ir.BlockId,
    };

    const FnCallPatch = struct {
        patch_offset: usize,
        target: []const u8,
    };

    alloc: std.mem.Allocator,
    asm_: x86.Asm,
    rodata: std.ArrayListUnmanaged(u8),
    reg_offsets: std.AutoHashMapUnmanaged(ir.Reg, i32),
    local_offsets: std.StringHashMapUnmanaged(i32),
    next_stack_offset: i32,
    block_offsets: std.AutoHashMapUnmanaged(ir.BlockId, usize),
    jump_patches: std.ArrayListUnmanaged(JumpPatch),
    is_entry: bool,
    rodata_patches: std.ArrayListUnmanaged(usize),
    fn_offsets: std.StringHashMapUnmanaged(usize),
    fn_call_patches: std.ArrayListUnmanaged(FnCallPatch),
    heap_ptr_offset: ?i32,
    // Break/continue: patches that need to be resolved when exiting a while loop
    break_patches: std.ArrayListUnmanaged(usize),
    continue_target: ?usize, // code offset of loop condition

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
            .heap_ptr_offset = null,
            .break_patches = .{},
            .continue_target = null,
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

        // Initialize heap for entry point
        if (is_entry) {
            self.emitHeapInit();
        }

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

            // ── Strings
            .string_byte_at => |sb| {
                self.loadReg(sb.str); // string ptr in rax
                self.asm_.movReg(.rcx, .rax);
                self.loadReg(sb.index); // index in rax
                // Load byte: movzx rax, byte [rcx + rax]
                self.asm_.addReg(.rcx, .rax); // rcx = str + index
                // movzx rax, byte [rcx] — zero-extend byte to 64-bit
                self.asm_.rexW(.rax, .rcx);
                self.asm_.emit(0x0F);
                self.asm_.emit(0xB6);
                self.asm_.emit(0x01); // modrm: mod=00, reg=rax, rm=rcx
                self.storeReg(sb.dest);
            },
            .string_len => |sl| {
                // For strings stored as (ptr, len), we'd need the len.
                // For now, this is a placeholder — string length needs to be tracked.
                _ = sl;
                self.asm_.movImm64(.rax, 0);
            },
            .string_eq => |se| {
                // Compare two strings byte-by-byte
                // First check lengths match
                self.loadReg(se.lhs_len);
                self.asm_.pushReg(.rax); // save lhs_len
                self.loadReg(se.rhs_len);
                self.asm_.movReg(.rcx, .rax); // rhs_len in rcx
                self.asm_.popReg(.rax); // lhs_len in rax
                self.asm_.cmpReg(.rax, .rcx);
                // If lengths differ, result is false
                self.asm_.movImm64(.rax, 0); // default false
                const len_neq = self.asm_.jneRel32();
                // Lengths match — compare bytes
                self.loadReg(se.lhs);
                self.asm_.pushReg(.rax); // save lhs ptr
                self.loadReg(se.rhs);
                self.asm_.movReg(.rsi, .rax); // rhs ptr in rsi
                self.asm_.popReg(.rdi); // lhs ptr in rdi
                self.loadReg(se.lhs_len);
                self.asm_.movReg(.rcx, .rax); // len in rcx
                // Loop: compare byte by byte
                self.asm_.movImm64(.rax, 1); // assume equal
                const loop_top = self.asm_.offset();
                self.asm_.testReg(.rcx);
                const loop_exit = self.asm_.jeRel32(); // if rcx==0, done (equal)
                // Compare one byte
                // movzx rdx, byte [rdi]
                self.asm_.rex(true, .rdx, .rdi);
                self.asm_.emit(0x0F);
                self.asm_.emit(0xB6);
                self.asm_.emit(0x17); // modrm: mod=00, reg=rdx, rm=rdi
                // movzx r8, byte [rsi]
                self.asm_.rex(true, .r8, .rsi);
                self.asm_.emit(0x0F);
                self.asm_.emit(0xB6);
                self.asm_.emit(0x06); // modrm: mod=00, reg=r8(0), rm=rsi
                self.asm_.cmpReg(.rdx, .r8);
                self.asm_.movImm64(.rax, 0);
                const not_eq = self.asm_.jneRel32();
                self.asm_.movImm64(.rax, 1); // still equal
                // Advance pointers
                self.asm_.addImm32(.rdi, 1);
                self.asm_.addImm32(.rsi, 1);
                self.asm_.subImm32(.rcx, 1);
                const back_patch = self.asm_.jmpRel32();
                self.asm_.patchRel32At(back_patch, loop_top);
                self.asm_.patchRel32(loop_exit);
                self.asm_.patchRel32(not_eq);
                self.asm_.patchRel32(len_neq);
                self.storeReg(se.dest);
            },

            // ── Lists
            .list_new => |ln| {
                // Allocate list header: [capacity(8)][length(8)][items(capacity*8)]
                // Initial capacity = 16 items = 16*8 + 16 = 144 bytes
                self.emitBumpAllocImm(16 + 16 * 8);
                // Set capacity = 16
                self.asm_.movImm64(.rcx, 16);
                self.asm_.storeIndirect(.rax, 0, .rcx);
                // Set length = 0
                self.asm_.movImm64(.rcx, 0);
                self.asm_.storeIndirect(.rax, 8, .rcx);
                self.storeReg(ln.dest);
            },
            .list_append => |la| {
                // Step 1: Load value into rdx (save it)
                self.loadReg(la.value);
                self.asm_.pushReg(.rax); // push value onto stack

                // Step 2: Load list base, get length, compute item address
                self.loadReg(la.list); // rax = list base
                self.asm_.loadIndirect(.rcx, .rax, 8); // rcx = length

                // Compute item offset: 16 + length * 8
                self.asm_.pushReg(.rax); // save base
                self.asm_.movReg(.rsi, .rcx); // rsi = length
                self.asm_.movImm64(.rdx, 8);
                self.asm_.imulReg(.rsi, .rdx); // rsi = length * 8
                self.asm_.addImm32(.rsi, 16); // rsi = 16 + length*8
                self.asm_.popReg(.rax); // restore base

                // Step 3: Store value at base + offset
                self.asm_.popReg(.rdx); // pop saved value
                self.asm_.addReg(.rax, .rsi); // rax = item address
                self.asm_.storeIndirect(.rax, 0, .rdx);

                // Step 4: Increment length
                self.loadReg(la.list); // reload base
                self.asm_.loadIndirect(.rcx, .rax, 8); // current length
                self.asm_.addImm32(.rcx, 1);
                self.asm_.storeIndirect(.rax, 8, .rcx); // store new length
            },
            .list_len => |ll| {
                self.loadReg(ll.list); // list base in rax
                self.asm_.loadIndirect(.rax, .rax, 8); // length at offset 8
                self.storeReg(ll.dest);
            },
            .list_get => |lg| {
                self.loadReg(lg.index); // index in rax
                self.asm_.movReg(.rcx, .rax); // index in rcx
                self.loadReg(lg.list); // base in rax
                // item at [base + 16 + index*8]
                self.asm_.pushReg(.rax); // save base
                self.asm_.movReg(.rsi, .rcx);
                self.asm_.movImm64(.rcx, 8);
                self.asm_.imulReg(.rsi, .rcx); // rsi = index*8
                self.asm_.addImm32(.rsi, 16); // rsi = 16 + index*8
                self.asm_.popReg(.rax); // base
                self.asm_.addReg(.rax, .rsi); // rax = base + offset
                self.asm_.loadIndirect(.rax, .rax, 0); // load value
                self.storeReg(lg.dest);
            },

            // ── Structs
            .struct_alloc => |sa| {
                // Reserve N*8 bytes on the stack, get base address
                const base_offset = self.next_stack_offset;
                self.next_stack_offset -= @as(i32, @intCast(sa.num_fields)) * 8;
                self.asm_.leaLocal32(.rax, base_offset);
                self.storeReg(sa.dest);
            },
            .struct_store => |ss| {
                self.loadReg(ss.src);
                self.asm_.movReg(.rcx, .rax); // value in rcx
                self.loadReg(ss.base); // base addr in rax
                self.asm_.storeIndirect(.rax, @intCast(ss.field_index * 8), .rcx);
            },
            .struct_load => |sl| {
                self.loadReg(sl.base); // base addr in rax
                self.asm_.loadIndirect(.rax, .rax, @intCast(sl.field_index * 8));
                self.storeReg(sl.dest);
            },

            // ── Break/continue (lowered to jumps, these shouldn't appear)
            .break_loop, .continue_loop => {},

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

    /// Emit the heap initialization code (mmap a large region).
    /// Must be called at the start of main.
    fn emitHeapInit(self: *LinuxX86Backend) void {
        // mmap(NULL, 1MB, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
        // syscall 9: rdi=addr, rsi=length, rdx=prot, r10=flags, r8=fd, r9=offset
        self.asm_.movImm64(.rdi, 0); // addr = NULL
        self.asm_.movImm64(.rsi, 1048576); // 1MB
        self.asm_.movImm64(.rdx, 3); // PROT_READ | PROT_WRITE
        self.asm_.movImm64(.r10, 0x22); // MAP_PRIVATE | MAP_ANONYMOUS
        self.asm_.movImm64(.r8, @bitCast(@as(i64, -1))); // fd = -1
        self.asm_.movImm64(.r9, 0); // offset = 0
        self.emitSyscall(9); // sys_mmap
        // rax = heap base. Store as bump pointer.
        const offset = self.next_stack_offset;
        self.next_stack_offset -= 8;
        self.heap_ptr_offset = offset;
        self.asm_.storeLocal32(offset, .rax);
    }

    /// Allocate n bytes from the bump heap. Returns address in rax.
    fn emitBumpAlloc(self: *LinuxX86Backend, size_reg: x86.Reg64) void {
        if (self.heap_ptr_offset) |hp_offset| {
            // Load current heap pointer
            self.asm_.loadLocal32(.rax, hp_offset);
            // Save current pointer (allocation result)
            self.asm_.pushReg(.rax);
            // Advance: heap_ptr += size
            self.asm_.addReg(.rax, size_reg);
            self.asm_.storeLocal32(hp_offset, .rax);
            // Return the old pointer
            self.asm_.popReg(.rax);
        }
    }

    /// Allocate a fixed number of bytes from the bump heap.
    fn emitBumpAllocImm(self: *LinuxX86Backend, size: i64) void {
        self.asm_.movImm64(.rcx, size);
        self.emitBumpAlloc(.rcx);
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
        // String classification builtins
        if (std.mem.eql(u8, name, "string_is_alpha") or
            std.mem.eql(u8, name, "string_is_digit") or
            std.mem.eql(u8, name, "string_is_whitespace") or
            std.mem.eql(u8, name, "string_is_alnum"))
        {
            if (args.len >= 1) {
                // Load first byte of the string
                self.loadReg(args[0]); // string ptr in rax
                self.asm_.rex(true, .rax, .rax);
                self.asm_.emit(0x0F);
                self.asm_.emit(0xB6);
                self.asm_.emit(0x00); // movzx rax, byte [rax]
                // rax = first byte

                if (std.mem.eql(u8, name, "string_is_digit")) {
                    // b >= '0' && b <= '9' → b >= 48 && b <= 57
                    self.asm_.movReg(.rcx, .rax);
                    self.asm_.cmpImm32(.rcx, 48);
                    self.asm_.setge(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 57);
                    self.asm_.setle(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rcx);
                    self.asm_.andReg(.rax, .rcx);
                } else if (std.mem.eql(u8, name, "string_is_alpha")) {
                    // (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z')
                    self.asm_.movReg(.rcx, .rax);
                    // upper: 65-90
                    self.asm_.cmpImm32(.rcx, 65);
                    self.asm_.setge(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 90);
                    self.asm_.setle(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rdx);
                    self.asm_.andReg(.rax, .rdx); // is_upper
                    self.asm_.pushReg(.rax);
                    // lower: 97-122
                    self.asm_.cmpImm32(.rcx, 97);
                    self.asm_.setge(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 122);
                    self.asm_.setle(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rdx);
                    self.asm_.andReg(.rax, .rdx); // is_lower
                    self.asm_.popReg(.rdx); // is_upper
                    self.asm_.orReg(.rax, .rdx); // is_upper || is_lower
                } else if (std.mem.eql(u8, name, "string_is_whitespace")) {
                    // b == 32 || b == 9 || b == 10 || b == 13
                    self.asm_.movReg(.rcx, .rax);
                    self.asm_.cmpImm32(.rcx, 32);
                    self.asm_.sete(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 9);
                    self.asm_.sete(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rdx);
                    self.asm_.orReg(.rax, .rdx);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 10);
                    self.asm_.sete(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rdx);
                    self.asm_.orReg(.rax, .rdx);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 13);
                    self.asm_.sete(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rdx);
                    self.asm_.orReg(.rax, .rdx);
                } else {
                    // is_alnum = is_alpha || is_digit
                    // For simplicity, check 48-57 || 65-90 || 97-122
                    self.asm_.movReg(.rcx, .rax);
                    // digit
                    self.asm_.cmpImm32(.rcx, 48);
                    self.asm_.setge(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 57);
                    self.asm_.setle(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rdx);
                    self.asm_.andReg(.rax, .rdx);
                    self.asm_.pushReg(.rax); // is_digit on stack
                    // upper
                    self.asm_.cmpImm32(.rcx, 65);
                    self.asm_.setge(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 90);
                    self.asm_.setle(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rdx);
                    self.asm_.andReg(.rax, .rdx);
                    self.asm_.popReg(.rdx); // is_digit
                    self.asm_.orReg(.rax, .rdx);
                    self.asm_.pushReg(.rax); // is_digit || is_upper
                    // lower
                    self.asm_.cmpImm32(.rcx, 97);
                    self.asm_.setge(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.pushReg(.rax);
                    self.asm_.cmpImm32(.rcx, 122);
                    self.asm_.setle(.rax);
                    self.asm_.movzxByte(.rax, .rax);
                    self.asm_.popReg(.rdx);
                    self.asm_.andReg(.rax, .rdx);
                    self.asm_.popReg(.rdx);
                    self.asm_.orReg(.rax, .rdx);
                }
                self.storeReg(dest);
                return;
            }
        }

        // Set.has → linear scan using dedicated stack slots for temporaries
        if (std.mem.eql(u8, name, "set_has")) {
            if (args.len >= 2) {
                // Allocate temp stack slots
                const tmp_base = self.next_stack_offset;
                self.next_stack_offset -= 8; // tmp[0] = set ptr
                const tmp_len = self.next_stack_offset;
                self.next_stack_offset -= 8; // tmp[1] = length
                const tmp_idx = self.next_stack_offset;
                self.next_stack_offset -= 8; // tmp[2] = index
                const tmp_target = self.next_stack_offset;
                self.next_stack_offset -= 8; // tmp[3] = target value

                // Store set ptr and target value
                self.loadReg(args[0]);
                self.asm_.storeLocal32(tmp_base, .rax);
                self.asm_.loadIndirect(.rcx, .rax, 8); // length
                self.asm_.storeLocal32(tmp_len, .rcx);
                self.loadReg(args[1]);
                self.asm_.storeLocal32(tmp_target, .rax);
                self.asm_.movImm64(.rax, 0);
                self.asm_.storeLocal32(tmp_idx, .rax); // index = 0

                // Result = 0 (not found)
                self.asm_.movImm64(.rax, 0);
                self.storeReg(dest);

                // Loop
                const loop_top = self.asm_.offset();
                self.asm_.loadLocal32(.rax, tmp_idx);
                self.asm_.loadLocal32(.rcx, tmp_len);
                self.asm_.cmpReg(.rax, .rcx);
                const done_patch = self.asm_.jgeRel32();

                // Load element: base + 16 + index*8
                self.asm_.loadLocal32(.rcx, tmp_idx);
                self.asm_.movImm64(.rdx, 8);
                self.asm_.imulReg(.rcx, .rdx);
                self.asm_.addImm32(.rcx, 16);
                self.asm_.loadLocal32(.rax, tmp_base);
                self.asm_.addReg(.rax, .rcx);
                self.asm_.loadIndirect(.rax, .rax, 0); // element

                // Compare with target
                self.asm_.loadLocal32(.rcx, tmp_target);
                self.asm_.cmpReg(.rax, .rcx);
                const not_eq = self.asm_.jneRel32();

                // Found! result = 1, jump to end
                self.asm_.movImm64(.rax, 1);
                self.storeReg(dest);
                const found_patch = self.asm_.jmpRel32(); // will patch to end

                // Not equal — increment index, loop back
                self.asm_.patchRel32(not_eq);
                self.asm_.loadLocal32(.rax, tmp_idx);
                self.asm_.addImm32(.rax, 1);
                self.asm_.storeLocal32(tmp_idx, .rax);
                const back_patch = self.asm_.jmpRel32();
                self.asm_.patchRel32At(back_patch, loop_top);

                // End: both done_patch and found_patch land here
                self.asm_.patchRel32(done_patch);
                self.asm_.patchRel32(found_patch);
                return;
            }
        }

        // String.slice → copy substring to new heap allocation
        if (std.mem.eql(u8, name, "string_slice")) {
            if (args.len >= 3) {
                // args: str_ptr, start_index, end_index
                // Result: new string ptr pointing to str_ptr + start
                // Length = end - start
                self.loadReg(args[0]); // str ptr
                self.asm_.pushReg(.rax);
                self.loadReg(args[1]); // start
                self.asm_.popReg(.rcx); // str ptr in rcx
                self.asm_.addReg(.rax, .rcx); // rax = str + start = new ptr
                self.storeReg(dest);
                // Also need to track length for later use
                // For now, the caller knows the length from end-start
                return;
            }
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
