const std = @import("std");

/// x86_64 machine code assembler.
/// Emits raw instruction bytes into a buffer.

pub const Reg64 = enum(u4) {
    rax = 0,
    rcx = 1,
    rdx = 2,
    rbx = 3,
    rsp = 4,
    rbp = 5,
    rsi = 6,
    rdi = 7,
    r8 = 8,
    r9 = 9,
    r10 = 10,
    r11 = 11,
    r12 = 12,
    r13 = 13,
    r14 = 14,
    r15 = 15,

    pub fn low3(self: Reg64) u3 {
        return @truncate(@intFromEnum(self));
    }

    pub fn needsRex(self: Reg64) bool {
        return @intFromEnum(self) >= 8;
    }
};

pub const Asm = struct {
    code: std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Asm {
        return .{ .code = .{}, .alloc = alloc };
    }

    pub fn emit(self: *Asm, byte: u8) void {
        self.code.append(self.alloc, byte) catch {};
    }

    pub fn emit2(self: *Asm, a: u8, b: u8) void {
        self.emit(a);
        self.emit(b);
    }

    pub fn emitSlice(self: *Asm, bytes: []const u8) void {
        self.code.appendSlice(self.alloc, bytes) catch {};
    }

    pub fn emitU32(self: *Asm, val: u32) void {
        const bytes: [4]u8 = @bitCast(val);
        self.emitSlice(&bytes);
    }

    pub fn emitI32(self: *Asm, val: i32) void {
        const bytes: [4]u8 = @bitCast(val);
        self.emitSlice(&bytes);
    }

    pub fn emitU64(self: *Asm, val: u64) void {
        const bytes: [8]u8 = @bitCast(val);
        self.emitSlice(&bytes);
    }

    pub fn emitI64(self: *Asm, val: i64) void {
        const bytes: [8]u8 = @bitCast(val);
        self.emitSlice(&bytes);
    }

    /// REX prefix for 64-bit operand size
    pub fn rex(self: *Asm, w: bool, r: Reg64, b: Reg64) void {
        var byte: u8 = 0x40;
        if (w) byte |= 0x08; // W bit — 64-bit operand
        if (r.needsRex()) byte |= 0x04; // R bit — extends ModR/M reg
        if (b.needsRex()) byte |= 0x01; // B bit — extends ModR/M r/m
        self.emit(byte);
    }

    pub fn rexW(self: *Asm, r: Reg64, b: Reg64) void {
        self.rex(true, r, b);
    }

    /// ModR/M byte: mod=11 (register-register), reg, r/m
    pub fn modrm(self: *Asm, reg: Reg64, rm: Reg64) void {
        self.emit(0xC0 | (@as(u8, reg.low3()) << 3) | @as(u8, rm.low3()));
    }

    // ── Instructions ─────────────────────────────────────

    /// mov reg, imm64
    pub fn movImm64(self: *Asm, dst: Reg64, val: i64) void {
        self.rex(true, .rax, dst);
        self.emit(0xB8 + @as(u8, dst.low3())); // MOV r64, imm64
        self.emitI64(val);
    }

    /// mov dst, src (register to register)
    pub fn movReg(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(src, dst);
        self.emit(0x89); // MOV r/m64, r64
        self.modrm(src, dst);
    }

    /// add dst, src
    pub fn addReg(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(src, dst);
        self.emit(0x01); // ADD r/m64, r64
        self.modrm(src, dst);
    }

    /// sub dst, src
    pub fn subReg(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(src, dst);
        self.emit(0x29); // SUB r/m64, r64
        self.modrm(src, dst);
    }

    /// imul dst, src
    pub fn imulReg(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(dst, src);
        self.emit2(0x0F, 0xAF); // IMUL r64, r/m64
        self.modrm(dst, src);
    }

    /// cqo — sign extend rax into rdx:rax (for idiv)
    pub fn cqo(self: *Asm) void {
        self.rex(true, .rax, .rax);
        self.emit(0x99);
    }

    /// idiv src — signed divide rdx:rax by src, quotient in rax, remainder in rdx
    /// Encoding: REX.W F7 /7 (modrm reg field = 7)
    pub fn idivReg(self: *Asm, src: Reg64) void {
        self.rexW(.rax, src);
        self.emit(0xF7);
        self.emit(0xC0 | (7 << 3) | @as(u8, src.low3())); // /7 = IDIV
    }

    /// neg reg — negate
    /// Encoding: REX.W F7 /3
    pub fn negReg(self: *Asm, reg: Reg64) void {
        self.rexW(.rax, reg);
        self.emit(0xF7);
        self.emit(0xC0 | (3 << 3) | @as(u8, reg.low3())); // /3 = NEG
    }

    /// not reg — bitwise NOT
    /// Encoding: REX.W F7 /2
    pub fn notReg(self: *Asm, reg: Reg64) void {
        self.rexW(.rax, reg);
        self.emit(0xF7);
        self.emit(0xC0 | (2 << 3) | @as(u8, reg.low3())); // /2 = NOT
    }

    /// and dst, src
    pub fn andReg(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(src, dst);
        self.emit(0x21); // AND r/m64, r64
        self.modrm(src, dst);
    }

    /// or dst, src
    pub fn orReg(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(src, dst);
        self.emit(0x09); // OR r/m64, r64
        self.modrm(src, dst);
    }

    /// xor dst, src
    pub fn xorReg(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(src, dst);
        self.emit(0x31); // XOR r/m64, r64
        self.modrm(src, dst);
    }

    /// xor reg, imm8 (useful for bool flip: xor rax, 1)
    pub fn xorImm8(self: *Asm, dst: Reg64, val: u8) void {
        self.rexW(.rax, dst);
        self.emit(0x83);
        self.emit(0xC0 | (6 << 3) | @as(u8, dst.low3())); // /6 = XOR r/m64, imm8
        self.emit(val);
    }

    /// add reg, imm32
    pub fn addImm32(self: *Asm, dst: Reg64, val: i32) void {
        self.rexW(.rax, dst);
        self.emit(0x81);
        self.emit(0xC0 | @as(u8, dst.low3())); // /0 = ADD
        self.emitI32(val);
    }

    /// sub reg, imm32
    pub fn subImm32(self: *Asm, dst: Reg64, val: i32) void {
        self.rexW(.rax, dst);
        self.emit(0x81);
        self.emit(0xC0 | (5 << 3) | @as(u8, dst.low3())); // /5 = SUB
        self.emitI32(val);
    }

    /// cmp reg, imm32
    pub fn cmpImm32(self: *Asm, dst: Reg64, val: i32) void {
        self.rexW(.rax, dst);
        self.emit(0x81);
        self.emit(0xC0 | (7 << 3) | @as(u8, dst.low3())); // /7 = CMP
        self.emitI32(val);
    }

    /// cmove dst, src — conditional move if equal
    pub fn cmove(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(dst, src);
        self.emit2(0x0F, 0x44);
        self.modrm(dst, src);
    }

    /// cmovne dst, src — conditional move if not equal
    pub fn cmovne(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(dst, src);
        self.emit2(0x0F, 0x45);
        self.modrm(dst, src);
    }

    /// cmovl dst, src — conditional move if less
    pub fn cmovl(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(dst, src);
        self.emit2(0x0F, 0x4C);
        self.modrm(dst, src);
    }

    /// cmovg dst, src — conditional move if greater
    pub fn cmovg(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(dst, src);
        self.emit2(0x0F, 0x4F);
        self.modrm(dst, src);
    }

    /// cmovle dst, src — conditional move if less or equal
    pub fn cmovle(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(dst, src);
        self.emit2(0x0F, 0x4E);
        self.modrm(dst, src);
    }

    /// cmovge dst, src — conditional move if greater or equal
    pub fn cmovge(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(dst, src);
        self.emit2(0x0F, 0x4D);
        self.modrm(dst, src);
    }

    /// nop — no operation (1 byte)
    pub fn nop(self: *Asm) void {
        self.emit(0x90);
    }

    /// mov reg, imm32 (sign-extended to 64-bit) — shorter encoding for small constants
    pub fn movImm32(self: *Asm, dst: Reg64, val: i32) void {
        self.rexW(.rax, dst);
        self.emit(0xC7);
        self.emit(0xC0 | @as(u8, dst.low3())); // /0 = MOV r/m64, imm32
        self.emitI32(val);
    }

    /// cmp reg1, reg2
    pub fn cmpReg(self: *Asm, a: Reg64, b: Reg64) void {
        self.rexW(b, a);
        self.emit(0x39); // CMP r/m64, r64
        self.modrm(b, a);
    }

    /// sete dst — set byte if equal (after cmp)
    pub fn sete(self: *Asm, dst: Reg64) void {
        if (dst.needsRex()) self.rex(false, .rax, dst);
        self.emit2(0x0F, 0x94);
        self.emit(0xC0 | @as(u8, dst.low3()));
    }

    /// setne dst
    pub fn setne(self: *Asm, dst: Reg64) void {
        if (dst.needsRex()) self.rex(false, .rax, dst);
        self.emit2(0x0F, 0x95);
        self.emit(0xC0 | @as(u8, dst.low3()));
    }

    /// setl dst (less than, signed)
    pub fn setl(self: *Asm, dst: Reg64) void {
        if (dst.needsRex()) self.rex(false, .rax, dst);
        self.emit2(0x0F, 0x9C);
        self.emit(0xC0 | @as(u8, dst.low3()));
    }

    /// setg dst (greater than, signed)
    pub fn setg(self: *Asm, dst: Reg64) void {
        if (dst.needsRex()) self.rex(false, .rax, dst);
        self.emit2(0x0F, 0x9F);
        self.emit(0xC0 | @as(u8, dst.low3()));
    }

    /// setle dst
    pub fn setle(self: *Asm, dst: Reg64) void {
        if (dst.needsRex()) self.rex(false, .rax, dst);
        self.emit2(0x0F, 0x9E);
        self.emit(0xC0 | @as(u8, dst.low3()));
    }

    /// setge dst
    pub fn setge(self: *Asm, dst: Reg64) void {
        if (dst.needsRex()) self.rex(false, .rax, dst);
        self.emit2(0x0F, 0x9D);
        self.emit(0xC0 | @as(u8, dst.low3()));
    }

    /// movzx reg, reg8 — zero-extend byte to 64-bit (after setcc)
    pub fn movzxByte(self: *Asm, dst: Reg64, src: Reg64) void {
        self.rexW(dst, src);
        self.emit2(0x0F, 0xB6);
        self.modrm(dst, src);
    }

    /// push reg
    pub fn pushReg(self: *Asm, reg: Reg64) void {
        if (reg.needsRex()) self.rex(false, .rax, reg);
        self.emit(0x50 + @as(u8, reg.low3()));
    }

    /// pop reg
    pub fn popReg(self: *Asm, reg: Reg64) void {
        if (reg.needsRex()) self.rex(false, .rax, reg);
        self.emit(0x58 + @as(u8, reg.low3()));
    }

    /// ret
    pub fn ret(self: *Asm) void {
        self.emit(0xC3);
    }

    /// syscall
    pub fn syscall(self: *Asm) void {
        self.emit2(0x0F, 0x05);
    }

    /// jmp rel32 — returns offset of the rel32 to patch later
    pub fn jmpRel32(self: *Asm) usize {
        self.emit(0xE9);
        const patch_offset = self.code.items.len;
        self.emitI32(0); // placeholder
        return patch_offset;
    }

    /// je rel32 — jump if equal, returns offset to patch
    pub fn jeRel32(self: *Asm) usize {
        self.emit2(0x0F, 0x84);
        const patch_offset = self.code.items.len;
        self.emitI32(0);
        return patch_offset;
    }

    /// jne rel32 — jump if not equal, returns offset to patch
    pub fn jneRel32(self: *Asm) usize {
        self.emit2(0x0F, 0x85);
        const patch_offset = self.code.items.len;
        self.emitI32(0);
        return patch_offset;
    }

    /// Patch a rel32 at the given offset to jump to a specific target
    pub fn patchRel32At(self: *Asm, patch_offset: usize, target: usize) void {
        const rel: i32 = @intCast(@as(i64, @intCast(target)) - @as(i64, @intCast(patch_offset + 4)));
        const bytes: [4]u8 = @bitCast(rel);
        self.code.items[patch_offset] = bytes[0];
        self.code.items[patch_offset + 1] = bytes[1];
        self.code.items[patch_offset + 2] = bytes[2];
        self.code.items[patch_offset + 3] = bytes[3];
    }

    /// Patch a rel32 at the given offset to jump to the current position
    pub fn patchRel32(self: *Asm, patch_offset: usize) void {
        const target = self.code.items.len;
        const rel: i32 = @intCast(@as(i64, @intCast(target)) - @as(i64, @intCast(patch_offset + 4)));
        const bytes: [4]u8 = @bitCast(rel);
        self.code.items[patch_offset] = bytes[0];
        self.code.items[patch_offset + 1] = bytes[1];
        self.code.items[patch_offset + 2] = bytes[2];
        self.code.items[patch_offset + 3] = bytes[3];
    }

    /// test reg, reg — sets ZF if reg is zero
    pub fn testReg(self: *Asm, reg: Reg64) void {
        self.rexW(reg, reg);
        self.emit(0x85);
        self.modrm(reg, reg);
    }

    /// Current code offset
    pub fn offset(self: *Asm) usize {
        return self.code.items.len;
    }

    /// call rel32 — returns offset to patch
    pub fn callRel32(self: *Asm) usize {
        self.emit(0xE8);
        const patch_offset = self.code.items.len;
        self.emitI32(0);
        return patch_offset;
    }

    /// sub rsp, imm8
    pub fn subRspImm8(self: *Asm, val: u8) void {
        self.rex(true, .rax, .rsp);
        self.emit(0x83);
        self.emit(0xEC); // modrm: /5, rm=rsp
        self.emit(val);
    }

    /// add rsp, imm8
    pub fn addRspImm8(self: *Asm, val: u8) void {
        self.rex(true, .rax, .rsp);
        self.emit(0x83);
        self.emit(0xC4); // modrm: /0, rm=rsp
        self.emit(val);
    }

    /// mov [rbp - offset], reg
    pub fn storeLocal(self: *Asm, offset_val: i8, src: Reg64) void {
        self.rexW(src, .rbp);
        self.emit(0x89);
        self.emit(0x45 | (@as(u8, src.low3()) << 3)); // modrm: [rbp+disp8]
        self.emit(@bitCast(offset_val));
    }

    /// mov reg, [rbp - offset]
    pub fn loadLocal(self: *Asm, dst: Reg64, offset_val: i8) void {
        self.rexW(dst, .rbp);
        self.emit(0x8B);
        self.emit(0x45 | (@as(u8, dst.low3()) << 3)); // modrm: [rbp+disp8]
        self.emit(@bitCast(offset_val));
    }

    /// mov [rbp + disp32], reg — for larger stack frames
    pub fn storeLocal32(self: *Asm, offset_val: i32, src: Reg64) void {
        self.rexW(src, .rbp);
        self.emit(0x89);
        self.emit(0x85 | (@as(u8, src.low3()) << 3)); // modrm: mod=10 [rbp+disp32]
        self.emitI32(offset_val);
    }

    /// mov reg, [rbp + disp32] — for larger stack frames
    pub fn loadLocal32(self: *Asm, dst: Reg64, offset_val: i32) void {
        self.rexW(dst, .rbp);
        self.emit(0x8B);
        self.emit(0x85 | (@as(u8, dst.low3()) << 3)); // modrm: mod=10 [rbp+disp32]
        self.emitI32(offset_val);
    }

    /// lea dst, [rbp + disp32] — get address of stack slot
    pub fn leaLocal32(self: *Asm, dst: Reg64, offset_val: i32) void {
        self.rexW(dst, .rbp);
        self.emit(0x8D);
        self.emit(0x85 | (@as(u8, dst.low3()) << 3)); // modrm: mod=10 [rbp+disp32]
        self.emitI32(offset_val);
    }

    /// mov [base + disp32], src — store through pointer with offset
    pub fn storeIndirect(self: *Asm, base: Reg64, disp: i32, src: Reg64) void {
        self.rexW(src, base);
        self.emit(0x89);
        if (disp == 0 and base.low3() != 5) {
            // mod=00, no displacement (except rbp which always needs disp)
            self.emit(@as(u8, src.low3()) << 3 | @as(u8, base.low3()));
        } else {
            // mod=10, disp32
            self.emit(0x80 | (@as(u8, src.low3()) << 3) | @as(u8, base.low3()));
            self.emitI32(disp);
        }
    }

    /// mov dst, [base + disp32] — load through pointer with offset
    pub fn loadIndirect(self: *Asm, dst: Reg64, base: Reg64, disp: i32) void {
        self.rexW(dst, base);
        self.emit(0x8B);
        if (disp == 0 and base.low3() != 5) {
            self.emit(@as(u8, dst.low3()) << 3 | @as(u8, base.low3()));
        } else {
            self.emit(0x80 | (@as(u8, dst.low3()) << 3) | @as(u8, base.low3()));
            self.emitI32(disp);
        }
    }

    /// lea reg, [rip + disp32] — load effective address (for string constants)
    pub fn leaRipRel(self: *Asm, dst: Reg64) usize {
        self.rexW(dst, .rbp);
        self.emit(0x8D);
        self.emit(0x05 | (@as(u8, dst.low3()) << 3)); // modrm: [rip+disp32]
        const patch_offset = self.code.items.len;
        self.emitI32(0); // placeholder
        return patch_offset;
    }
};
