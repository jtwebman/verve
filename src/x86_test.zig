const std = @import("std");
const x86 = @import("x86.zig");
const testing = std.testing;
const Asm = x86.Asm;
const Reg64 = x86.Reg64;

// ── Helpers ──────────────────────────────────────────────

fn assemble(comptime f: fn (*Asm) void) []const u8 {
    var a = Asm.init(std.heap.page_allocator);
    f(&a);
    return a.code.items;
}

fn expectBytes(actual: []const u8, expected: []const u8) !void {
    if (!std.mem.eql(u8, actual, expected)) {
        std.debug.print("\nExpected: ", .{});
        for (expected) |b| std.debug.print("{x:0>2} ", .{b});
        std.debug.print("\nGot:      ", .{});
        for (actual) |b| std.debug.print("{x:0>2} ", .{b});
        std.debug.print("\n", .{});
    }
    try testing.expectEqualSlices(u8, expected, actual);
}

// ── MOV imm64 ────────────────────────────────────────────
// movabs rax, imm64 = REX.W(48) + B8 + imm64
// movabs rcx, imm64 = REX.W(48) + B9 + imm64
// movabs r8, imm64  = REX.WB(49) + B8 + imm64

test "mov rax, 0" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movImm64(.rax, 0); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0 });
}

test "mov rax, 42" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movImm64(.rax, 42); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0xB8, 42, 0, 0, 0, 0, 0, 0, 0 });
}

test "mov rcx, 1" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movImm64(.rcx, 1); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0xB9, 1, 0, 0, 0, 0, 0, 0, 0 });
}

test "mov rdi, 60" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movImm64(.rdi, 60); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0xBF, 60, 0, 0, 0, 0, 0, 0, 0 });
}

test "mov r8, 99" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movImm64(.r8, 99); }
    }.f);
    // r8 needs REX.WB = 0x49, and opcode B8+0 (r8 low3 = 0)
    try expectBytes(code, &.{ 0x49, 0xB8, 99, 0, 0, 0, 0, 0, 0, 0 });
}

test "mov rax, -1" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movImm64(.rax, -1); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0xB8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF });
}

// ── MOV reg, reg ─────────────────────────────────────────
// mov rax, rcx = REX.W(48) 89 C8 (89 /r, src=rcx(1), dst=rax(0))
// mov rcx, rax = REX.W(48) 89 C1

test "mov rax, rcx" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movReg(.rax, .rcx); }
    }.f);
    // 89 /r: modrm = 11_001_000 = C8 (src=rcx=1, dst=rax=0)
    try expectBytes(code, &.{ 0x48, 0x89, 0xC8 });
}

test "mov rcx, rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movReg(.rcx, .rax); }
    }.f);
    // 89 /r: modrm = 11_000_001 = C1 (src=rax=0, dst=rcx=1)
    try expectBytes(code, &.{ 0x48, 0x89, 0xC1 });
}

test "mov rbp, rsp" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movReg(.rbp, .rsp); }
    }.f);
    // 89 /r: modrm = 11_100_101 = E5 (src=rsp=4, dst=rbp=5)
    try expectBytes(code, &.{ 0x48, 0x89, 0xE5 });
}

// ── ADD ──────────────────────────────────────────────────
// add rax, rcx = REX.W(48) 01 C8

test "add rax, rcx" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.addReg(.rax, .rcx); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0x01, 0xC8 });
}

test "add rcx, rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.addReg(.rcx, .rax); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0x01, 0xC1 });
}

// ── SUB ──────────────────────────────────────────────────
// sub rax, rcx = REX.W(48) 29 C8

test "sub rax, rcx" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.subReg(.rax, .rcx); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0x29, 0xC8 });
}

// ── IMUL ─────────────────────────────────────────────────
// imul rax, rcx = REX.W(48) 0F AF C1

test "imul rax, rcx" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.imulReg(.rax, .rcx); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0x0F, 0xAF, 0xC1 });
}

// ── NEG ──────────────────────────────────────────────────
// neg rax = REX.W(48) F7 D8 (F7 /3, rm=rax=0, reg=3)

test "neg rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.negReg(.rax); }
    }.f);
    // F7 /3: modrm = 11_011_000 = D8
    try expectBytes(code, &.{ 0x48, 0xF7, 0xD8 });
}

// ── CMP ──────────────────────────────────────────────────
// cmp rax, rcx = REX.W(48) 39 C8

test "cmp rax, rcx" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.cmpReg(.rax, .rcx); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0x39, 0xC8 });
}

// ── SETcc ────────────────────────────────────────────────
// sete al = 0F 94 C0
// setne al = 0F 95 C0
// setl al = 0F 9C C0

test "sete rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.sete(.rax); }
    }.f);
    try expectBytes(code, &.{ 0x0F, 0x94, 0xC0 });
}

test "setne rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.setne(.rax); }
    }.f);
    try expectBytes(code, &.{ 0x0F, 0x95, 0xC0 });
}

test "setl rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.setl(.rax); }
    }.f);
    try expectBytes(code, &.{ 0x0F, 0x9C, 0xC0 });
}

test "setg rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.setg(.rax); }
    }.f);
    try expectBytes(code, &.{ 0x0F, 0x9F, 0xC0 });
}

// ── MOVZX ────────────────────────────────────────────────
// movzx rax, al = REX.W(48) 0F B6 C0

test "movzx rax, al" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movzxByte(.rax, .rax); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0x0F, 0xB6, 0xC0 });
}

// ── PUSH / POP ───────────────────────────────────────────
// push rax = 50
// push rbp = 55
// push r8 = 41 50 (REX.B + 50)
// pop rax = 58
// pop rbp = 5D

test "push rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.pushReg(.rax); }
    }.f);
    try expectBytes(code, &.{0x50});
}

test "push rbp" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.pushReg(.rbp); }
    }.f);
    try expectBytes(code, &.{0x55});
}

test "push r8" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.pushReg(.r8); }
    }.f);
    // r8 needs REX.B = 0x41, opcode 50+0
    try expectBytes(code, &.{ 0x41, 0x50 });
}

test "pop rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.popReg(.rax); }
    }.f);
    try expectBytes(code, &.{0x58});
}

test "pop rbp" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.popReg(.rbp); }
    }.f);
    try expectBytes(code, &.{0x5D});
}

// ── RET ──────────────────────────────────────────────────

test "ret" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.ret(); }
    }.f);
    try expectBytes(code, &.{0xC3});
}

// ── SYSCALL ──────────────────────────────────────────────

test "syscall" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.syscall(); }
    }.f);
    try expectBytes(code, &.{ 0x0F, 0x05 });
}

// ── CQO ──────────────────────────────────────────────────
// cqo = REX.W(48) 99

test "cqo" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.cqo(); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0x99 });
}

// ── TEST ─────────────────────────────────────────────────
// test rax, rax = REX.W(48) 85 C0

test "test rax, rax" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.testReg(.rax); }
    }.f);
    try expectBytes(code, &.{ 0x48, 0x85, 0xC0 });
}

// ── JMP rel32 ────────────────────────────────────────────

test "jmp rel32 produces 5 bytes" {
    const code = assemble(struct {
        fn f(a: *Asm) void { _ = a.jmpRel32(); }
    }.f);
    try testing.expectEqual(@as(usize, 5), code.len);
    try testing.expectEqual(@as(u8, 0xE9), code[0]);
}

// ── JE rel32 ─────────────────────────────────────────────

test "je rel32 produces 6 bytes" {
    const code = assemble(struct {
        fn f(a: *Asm) void { _ = a.jeRel32(); }
    }.f);
    try testing.expectEqual(@as(usize, 6), code.len);
    try testing.expectEqual(@as(u8, 0x0F), code[0]);
    try testing.expectEqual(@as(u8, 0x84), code[1]);
}

// ── Patch rel32 ──────────────────────────────────────────

test "patchRel32 computes correct offset" {
    var a = Asm.init(std.heap.page_allocator);
    // Emit a jmp with placeholder
    const patch = a.jmpRel32();
    // Emit some padding (10 bytes)
    var i: usize = 0;
    while (i < 10) : (i += 1) a.emit(0x90); // NOP
    // Patch the jump to land here
    a.patchRel32(patch);
    // The rel32 should be 10 (skip 10 NOPs)
    const rel_bytes = a.code.items[patch .. patch + 4];
    const rel: i32 = @bitCast(rel_bytes[0..4].*);
    try testing.expectEqual(@as(i32, 10), rel);
}

// ── SUB/ADD RSP ──────────────────────────────────────────

test "sub rsp, 64" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.subRspImm8(64); }
    }.f);
    // REX.W(48) 83 EC 40
    try expectBytes(code, &.{ 0x48, 0x83, 0xEC, 0x40 });
}

test "add rsp, 64" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.addRspImm8(64); }
    }.f);
    // REX.W(48) 83 C4 40
    try expectBytes(code, &.{ 0x48, 0x83, 0xC4, 0x40 });
}

// ── Function prologue/epilogue pattern ───────────────────

test "standard function prologue" {
    const code = assemble(struct {
        fn f(a: *Asm) void {
            a.pushReg(.rbp);
            a.movReg(.rbp, .rsp);
            a.subRspImm8(16);
        }
    }.f);
    try expectBytes(code, &.{
        0x55, // push rbp
        0x48, 0x89, 0xE5, // mov rbp, rsp
        0x48, 0x83, 0xEC, 0x10, // sub rsp, 16
    });
}

test "standard function epilogue" {
    const code = assemble(struct {
        fn f(a: *Asm) void {
            a.movReg(.rsp, .rbp);
            a.popReg(.rbp);
            a.ret();
        }
    }.f);
    try expectBytes(code, &.{
        0x48, 0x89, 0xEC, // mov rsp, rbp
        0x5D, // pop rbp
        0xC3, // ret
    });
}

// ── Linux syscall pattern ────────────────────────────────

test "exit(0) syscall sequence" {
    const code = assemble(struct {
        fn f(a: *Asm) void {
            a.movImm64(.rax, 60); // sys_exit
            a.movImm64(.rdi, 0); // exit code 0
            a.syscall();
        }
    }.f);
    // Should be: mov rax, 60 + mov rdi, 0 + syscall
    try testing.expectEqual(@as(usize, 22), code.len); // 10 + 10 + 2
    // Verify syscall at end
    try testing.expectEqual(@as(u8, 0x0F), code[20]);
    try testing.expectEqual(@as(u8, 0x05), code[21]);
}

test "write(1, buf, len) syscall sequence" {
    const code = assemble(struct {
        fn f(a: *Asm) void {
            a.movImm64(.rax, 1); // sys_write
            a.movImm64(.rdi, 1); // fd = stdout
            a.movImm64(.rsi, 0x400100); // buf address
            a.movImm64(.rdx, 13); // length
            a.syscall();
        }
    }.f);
    // 4 movImm64 (10 bytes each) + syscall (2 bytes) = 42 bytes
    try testing.expectEqual(@as(usize, 42), code.len);
}

// ── REX prefix correctness for r8-r15 ───────────────────

test "mov r9, r10 uses correct REX" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.movReg(.r9, .r10); }
    }.f);
    // r10 (src) needs REX.R, r9 (dst) needs REX.B
    // REX = 0x40 | W(0x08) | R(0x04) | B(0x01) = 0x4D
    // 89 /r: modrm = 11_010_001 = D1 (src=r10 low3=2, dst=r9 low3=1)
    try expectBytes(code, &.{ 0x4D, 0x89, 0xD1 });
}

test "add r8, r9 uses correct REX" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.addReg(.r8, .r9); }
    }.f);
    // r9 (src) needs REX.R, r8 (dst) needs REX.B
    // REX = 0x4D, 01 /r, modrm = 11_001_000 = C8
    try expectBytes(code, &.{ 0x4D, 0x01, 0xC8 });
}

test "push r15" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.pushReg(.r15); }
    }.f);
    // REX.B(0x41) + 50+7 = 57
    try expectBytes(code, &.{ 0x41, 0x57 });
}

test "pop r12" {
    const code = assemble(struct {
        fn f(a: *Asm) void { a.popReg(.r12); }
    }.f);
    // REX.B(0x41) + 58+4 = 5C
    try expectBytes(code, &.{ 0x41, 0x5C });
}
