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

// ════════════════════════════════════════════════════════════
// MOV imm64 — REX.W + B8+rd + imm64
// ════════════════════════════════════════════════════════════

test "movImm64 rax, 0" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rax, 0); } }.f), &.{ 0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 rax, 42" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rax, 42); } }.f), &.{ 0x48, 0xB8, 42, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 rcx, 1" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rcx, 1); } }.f), &.{ 0x48, 0xB9, 1, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 rdx, 2" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rdx, 2); } }.f), &.{ 0x48, 0xBA, 2, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 rbx, 3" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rbx, 3); } }.f), &.{ 0x48, 0xBB, 3, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 rsi, 6" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rsi, 6); } }.f), &.{ 0x48, 0xBE, 6, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 rdi, 60" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rdi, 60); } }.f), &.{ 0x48, 0xBF, 60, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 r8, 99 (REX.WB)" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.r8, 99); } }.f), &.{ 0x49, 0xB8, 99, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 r9, 7 (REX.WB)" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.r9, 7); } }.f), &.{ 0x49, 0xB9, 7, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 r15, 15 (REX.WB)" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.r15, 15); } }.f), &.{ 0x49, 0xBF, 15, 0, 0, 0, 0, 0, 0, 0 });
}

test "movImm64 rax, -1" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rax, -1); } }.f), &.{ 0x48, 0xB8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF });
}

test "movImm64 rax, max i64" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm64(.rax, 0x7FFFFFFFFFFFFFFF); } }.f), &.{ 0x48, 0xB8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F });
}

// ════════════════════════════════════════════════════════════
// MOV imm32 (sign-extended) — shorter encoding for small values
// REX.W + C7 /0 + imm32
// ════════════════════════════════════════════════════════════

test "movImm32 rax, 0" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm32(.rax, 0); } }.f), &.{ 0x48, 0xC7, 0xC0, 0, 0, 0, 0 });
}

test "movImm32 rcx, 100" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movImm32(.rcx, 100); } }.f), &.{ 0x48, 0xC7, 0xC1, 100, 0, 0, 0 });
}

// ════════════════════════════════════════════════════════════
// MOV reg, reg — REX.W + 89 /r
// ════════════════════════════════════════════════════════════

test "movReg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movReg(.rax, .rcx); } }.f), &.{ 0x48, 0x89, 0xC8 });
}

test "movReg rcx, rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movReg(.rcx, .rax); } }.f), &.{ 0x48, 0x89, 0xC1 });
}

test "movReg rbp, rsp" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movReg(.rbp, .rsp); } }.f), &.{ 0x48, 0x89, 0xE5 });
}

test "movReg rsp, rbp" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movReg(.rsp, .rbp); } }.f), &.{ 0x48, 0x89, 0xEC });
}

test "movReg r9, r10 (REX.WRB)" {
    // src=r10 needs REX.R, dst=r9 needs REX.B
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movReg(.r9, .r10); } }.f), &.{ 0x4D, 0x89, 0xD1 });
}

test "movReg rax, r8 (REX.WR)" {
    // src=r8 needs REX.R, dst=rax no extra
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movReg(.rax, .r8); } }.f), &.{ 0x4C, 0x89, 0xC0 });
}

test "movReg r8, rax (REX.WB)" {
    // src=rax no extra, dst=r8 needs REX.B
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movReg(.r8, .rax); } }.f), &.{ 0x49, 0x89, 0xC0 });
}

// ════════════════════════════════════════════════════════════
// ADD reg, reg — REX.W + 01 /r
// ════════════════════════════════════════════════════════════

test "addReg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.addReg(.rax, .rcx); } }.f), &.{ 0x48, 0x01, 0xC8 });
}

test "addReg r8, r9 (REX.WRB)" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.addReg(.r8, .r9); } }.f), &.{ 0x4D, 0x01, 0xC8 });
}

// ════════════════════════════════════════════════════════════
// ADD reg, imm32 — REX.W + 81 /0 + imm32
// ════════════════════════════════════════════════════════════

test "addImm32 rax, 100" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.addImm32(.rax, 100); } }.f), &.{ 0x48, 0x81, 0xC0, 100, 0, 0, 0 });
}

test "addImm32 rcx, -1" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.addImm32(.rcx, -1); } }.f), &.{ 0x48, 0x81, 0xC1, 0xFF, 0xFF, 0xFF, 0xFF });
}

// ════════════════════════════════════════════════════════════
// SUB reg, reg — REX.W + 29 /r
// SUB reg, imm32 — REX.W + 81 /5 + imm32
// ════════════════════════════════════════════════════════════

test "subReg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.subReg(.rax, .rcx); } }.f), &.{ 0x48, 0x29, 0xC8 });
}

test "subImm32 rax, 256" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.subImm32(.rax, 256); } }.f), &.{ 0x48, 0x81, 0xE8, 0, 1, 0, 0 });
}

// ════════════════════════════════════════════════════════════
// IMUL reg, reg — REX.W + 0F AF /r
// ════════════════════════════════════════════════════════════

test "imulReg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.imulReg(.rax, .rcx); } }.f), &.{ 0x48, 0x0F, 0xAF, 0xC1 });
}

test "imulReg rdx, rsi" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.imulReg(.rdx, .rsi); } }.f), &.{ 0x48, 0x0F, 0xAF, 0xD6 });
}

// ════════════════════════════════════════════════════════════
// IDIV reg — REX.W + F7 /7
// ════════════════════════════════════════════════════════════

test "idivReg rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.idivReg(.rcx); } }.f), &.{ 0x48, 0xF7, 0xF9 });
    // F7 /7: modrm = 11_111_001 = F9 (reg=7, rm=rcx=1)
}

test "idivReg rbx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.idivReg(.rbx); } }.f), &.{ 0x48, 0xF7, 0xFB });
    // modrm = 11_111_011 = FB (reg=7, rm=rbx=3)
}

test "idivReg r8 (REX.WB)" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.idivReg(.r8); } }.f), &.{ 0x49, 0xF7, 0xF8 });
}

// ════════════════════════════════════════════════════════════
// CQO — REX.W + 99
// ════════════════════════════════════════════════════════════

test "cqo" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cqo(); } }.f), &.{ 0x48, 0x99 });
}

// ════════════════════════════════════════════════════════════
// Division pattern: cqo + idiv rcx
// ════════════════════════════════════════════════════════════

test "division sequence: cqo + idiv rcx" {
    try expectBytes(assemble(struct {
        fn f(a: *Asm) void {
            a.cqo();
            a.idivReg(.rcx);
        }
    }.f), &.{ 0x48, 0x99, 0x48, 0xF7, 0xF9 });
}

// ════════════════════════════════════════════════════════════
// NEG — REX.W + F7 /3
// ════════════════════════════════════════════════════════════

test "negReg rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.negReg(.rax); } }.f), &.{ 0x48, 0xF7, 0xD8 });
}

test "negReg rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.negReg(.rcx); } }.f), &.{ 0x48, 0xF7, 0xD9 });
}

// ════════════════════════════════════════════════════════════
// NOT — REX.W + F7 /2
// ════════════════════════════════════════════════════════════

test "notReg rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.notReg(.rax); } }.f), &.{ 0x48, 0xF7, 0xD0 });
    // modrm = 11_010_000 = D0 (reg=2, rm=rax=0)
}

// ════════════════════════════════════════════════════════════
// AND/OR/XOR reg, reg
// ════════════════════════════════════════════════════════════

test "andReg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.andReg(.rax, .rcx); } }.f), &.{ 0x48, 0x21, 0xC8 });
}

test "orReg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.orReg(.rax, .rcx); } }.f), &.{ 0x48, 0x09, 0xC8 });
}

test "xorReg rax, rax (zero idiom)" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.xorReg(.rax, .rax); } }.f), &.{ 0x48, 0x31, 0xC0 });
}

test "xorReg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.xorReg(.rax, .rcx); } }.f), &.{ 0x48, 0x31, 0xC8 });
}

test "xorImm8 rax, 1 (bool flip)" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.xorImm8(.rax, 1); } }.f), &.{ 0x48, 0x83, 0xF0, 1 });
}

// ════════════════════════════════════════════════════════════
// CMP reg, reg — REX.W + 39 /r
// CMP reg, imm32 — REX.W + 81 /7 + imm32
// ════════════════════════════════════════════════════════════

test "cmpReg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmpReg(.rax, .rcx); } }.f), &.{ 0x48, 0x39, 0xC8 });
}

test "cmpReg rdx, rbx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmpReg(.rdx, .rbx); } }.f), &.{ 0x48, 0x39, 0xDA });
}

test "cmpImm32 rax, 0" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmpImm32(.rax, 0); } }.f), &.{ 0x48, 0x81, 0xF8, 0, 0, 0, 0 });
}

test "cmpImm32 rcx, 42" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmpImm32(.rcx, 42); } }.f), &.{ 0x48, 0x81, 0xF9, 42, 0, 0, 0 });
}

// ════════════════════════════════════════════════════════════
// SETcc — 0F 9x /0
// ════════════════════════════════════════════════════════════

test "sete rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.sete(.rax); } }.f), &.{ 0x0F, 0x94, 0xC0 });
}

test "setne rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.setne(.rax); } }.f), &.{ 0x0F, 0x95, 0xC0 });
}

test "setl rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.setl(.rax); } }.f), &.{ 0x0F, 0x9C, 0xC0 });
}

test "setg rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.setg(.rax); } }.f), &.{ 0x0F, 0x9F, 0xC0 });
}

test "setle rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.setle(.rax); } }.f), &.{ 0x0F, 0x9E, 0xC0 });
}

test "setge rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.setge(.rax); } }.f), &.{ 0x0F, 0x9D, 0xC0 });
}

test "sete r8 (needs REX)" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.sete(.r8); } }.f), &.{ 0x41, 0x0F, 0x94, 0xC0 });
}

// ════════════════════════════════════════════════════════════
// CMOVcc — REX.W + 0F 4x /r
// ════════════════════════════════════════════════════════════

test "cmove rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmove(.rax, .rcx); } }.f), &.{ 0x48, 0x0F, 0x44, 0xC1 });
}

test "cmovne rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmovne(.rax, .rcx); } }.f), &.{ 0x48, 0x0F, 0x45, 0xC1 });
}

test "cmovl rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmovl(.rax, .rcx); } }.f), &.{ 0x48, 0x0F, 0x4C, 0xC1 });
}

test "cmovg rax, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmovg(.rax, .rcx); } }.f), &.{ 0x48, 0x0F, 0x4F, 0xC1 });
}

test "cmovle rax, rdx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmovle(.rax, .rdx); } }.f), &.{ 0x48, 0x0F, 0x4E, 0xC2 });
}

test "cmovge rax, rdx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.cmovge(.rax, .rdx); } }.f), &.{ 0x48, 0x0F, 0x4D, 0xC2 });
}

// ════════════════════════════════════════════════════════════
// MOVZX — REX.W + 0F B6 /r
// ════════════════════════════════════════════════════════════

test "movzxByte rax, rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movzxByte(.rax, .rax); } }.f), &.{ 0x48, 0x0F, 0xB6, 0xC0 });
}

test "movzxByte rdx, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.movzxByte(.rdx, .rcx); } }.f), &.{ 0x48, 0x0F, 0xB6, 0xD1 });
}

// ════════════════════════════════════════════════════════════
// PUSH/POP — 50+rd / 58+rd (REX.B for r8-r15)
// ════════════════════════════════════════════════════════════

test "push rax" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.rax); } }.f), &.{0x50}); }
test "push rcx" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.rcx); } }.f), &.{0x51}); }
test "push rdx" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.rdx); } }.f), &.{0x52}); }
test "push rbx" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.rbx); } }.f), &.{0x53}); }
test "push rsp" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.rsp); } }.f), &.{0x54}); }
test "push rbp" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.rbp); } }.f), &.{0x55}); }
test "push rsi" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.rsi); } }.f), &.{0x56}); }
test "push rdi" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.rdi); } }.f), &.{0x57}); }
test "push r8" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.r8); } }.f), &.{ 0x41, 0x50 }); }
test "push r9" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.r9); } }.f), &.{ 0x41, 0x51 }); }
test "push r12" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.r12); } }.f), &.{ 0x41, 0x54 }); }
test "push r15" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.pushReg(.r15); } }.f), &.{ 0x41, 0x57 }); }

test "pop rax" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.popReg(.rax); } }.f), &.{0x58}); }
test "pop rbp" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.popReg(.rbp); } }.f), &.{0x5D}); }
test "pop r8" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.popReg(.r8); } }.f), &.{ 0x41, 0x58 }); }
test "pop r12" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.popReg(.r12); } }.f), &.{ 0x41, 0x5C }); }
test "pop r15" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.popReg(.r15); } }.f), &.{ 0x41, 0x5F }); }

// ════════════════════════════════════════════════════════════
// TEST — REX.W + 85 /r
// ════════════════════════════════════════════════════════════

test "test rax, rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.testReg(.rax); } }.f), &.{ 0x48, 0x85, 0xC0 });
}

test "test rcx, rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.testReg(.rcx); } }.f), &.{ 0x48, 0x85, 0xC9 });
}

// ════════════════════════════════════════════════════════════
// RET, SYSCALL, NOP
// ════════════════════════════════════════════════════════════

test "ret" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.ret(); } }.f), &.{0xC3}); }
test "syscall" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.syscall(); } }.f), &.{ 0x0F, 0x05 }); }
test "nop" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.nop(); } }.f), &.{0x90}); }

// ════════════════════════════════════════════════════════════
// JMP/Jcc rel32 — structure tests
// ════════════════════════════════════════════════════════════

test "jmp rel32 opcode and size" {
    const code = assemble(struct { fn f(a: *Asm) void { _ = a.jmpRel32(); } }.f);
    try testing.expectEqual(@as(usize, 5), code.len);
    try testing.expectEqual(@as(u8, 0xE9), code[0]);
}

test "je rel32 opcode and size" {
    const code = assemble(struct { fn f(a: *Asm) void { _ = a.jeRel32(); } }.f);
    try testing.expectEqual(@as(usize, 6), code.len);
    try testing.expectEqual(@as(u8, 0x0F), code[0]);
    try testing.expectEqual(@as(u8, 0x84), code[1]);
}

test "jne rel32 opcode and size" {
    const code = assemble(struct { fn f(a: *Asm) void { _ = a.jneRel32(); } }.f);
    try testing.expectEqual(@as(usize, 6), code.len);
    try testing.expectEqual(@as(u8, 0x0F), code[0]);
    try testing.expectEqual(@as(u8, 0x85), code[1]);
}

test "call rel32 opcode and size" {
    const code = assemble(struct { fn f(a: *Asm) void { _ = a.callRel32(); } }.f);
    try testing.expectEqual(@as(usize, 5), code.len);
    try testing.expectEqual(@as(u8, 0xE8), code[0]);
}

// ════════════════════════════════════════════════════════════
// Patch rel32 — correctness
// ════════════════════════════════════════════════════════════

test "patchRel32 forward jump over 10 NOPs" {
    var a = Asm.init(std.heap.page_allocator);
    const patch = a.jmpRel32();
    var i: usize = 0;
    while (i < 10) : (i += 1) a.nop();
    a.patchRel32(patch);
    const rel: i32 = @bitCast(a.code.items[patch..][0..4].*);
    try testing.expectEqual(@as(i32, 10), rel);
}

test "patchRel32 backward jump" {
    var a = Asm.init(std.heap.page_allocator);
    const target = a.offset(); // position 0
    a.nop(); // 1 byte
    a.nop(); // 1 byte
    const patch = a.jmpRel32(); // 5 bytes, patch at offset 3
    a.patchRel32At(patch, target);
    const rel: i32 = @bitCast(a.code.items[patch..][0..4].*);
    // From end of jmp (offset 7) back to offset 0 = -7
    try testing.expectEqual(@as(i32, -7), rel);
}

test "patchRel32At to specific target" {
    var a = Asm.init(std.heap.page_allocator);
    const call_patch = a.callRel32();
    a.nop();
    a.nop();
    const target = a.offset();
    a.patchRel32At(call_patch, target);
    const rel: i32 = @bitCast(a.code.items[call_patch..][0..4].*);
    // From end of call (offset 5) to target (offset 7) = 2
    try testing.expectEqual(@as(i32, 2), rel);
}

// ════════════════════════════════════════════════════════════
// SUB/ADD RSP — stack frame management
// ════════════════════════════════════════════════════════════

test "subRspImm8 16" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.subRspImm8(16); } }.f), &.{ 0x48, 0x83, 0xEC, 0x10 }); }
test "subRspImm8 64" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.subRspImm8(64); } }.f), &.{ 0x48, 0x83, 0xEC, 0x40 }); }
test "addRspImm8 16" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.addRspImm8(16); } }.f), &.{ 0x48, 0x83, 0xC4, 0x10 }); }
test "addRspImm8 64" { try expectBytes(assemble(struct { fn f(a: *Asm) void { a.addRspImm8(64); } }.f), &.{ 0x48, 0x83, 0xC4, 0x40 }); }

// ════════════════════════════════════════════════════════════
// Store/Load local — [rbp + disp8]
// ════════════════════════════════════════════════════════════

test "storeLocal [rbp-8], rax" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.storeLocal(-8, .rax); } }.f), &.{ 0x48, 0x89, 0x45, 0xF8 });
    // 89 /r: modrm 01_000_101 = 45 (mod=01 disp8, reg=rax=0, rm=rbp=5), disp=-8 = 0xF8
}

test "storeLocal [rbp-16], rcx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.storeLocal(-16, .rcx); } }.f), &.{ 0x48, 0x89, 0x4D, 0xF0 });
    // modrm 01_001_101 = 4D (reg=rcx=1, rm=rbp=5), disp=-16 = 0xF0
}

test "storeLocal [rbp-24], rdx" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.storeLocal(-24, .rdx); } }.f), &.{ 0x48, 0x89, 0x55, 0xE8 });
}

test "loadLocal rax, [rbp-8]" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.loadLocal(.rax, -8); } }.f), &.{ 0x48, 0x8B, 0x45, 0xF8 });
    // 8B /r: modrm 01_000_101 = 45 (reg=rax=0, rm=rbp=5), disp=-8
}

test "loadLocal rcx, [rbp-16]" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.loadLocal(.rcx, -16); } }.f), &.{ 0x48, 0x8B, 0x4D, 0xF0 });
}

test "loadLocal rdi, [rbp-8]" {
    try expectBytes(assemble(struct { fn f(a: *Asm) void { a.loadLocal(.rdi, -8); } }.f), &.{ 0x48, 0x8B, 0x7D, 0xF8 });
}

// ════════════════════════════════════════════════════════════
// LEA rip-relative — REX.W + 8D /r [rip+disp32]
// ════════════════════════════════════════════════════════════

test "leaRipRel rax" {
    const code = assemble(struct { fn f(a: *Asm) void { _ = a.leaRipRel(.rax); } }.f);
    try testing.expectEqual(@as(usize, 7), code.len);
    try testing.expectEqual(@as(u8, 0x48), code[0]); // REX.W
    try testing.expectEqual(@as(u8, 0x8D), code[1]); // LEA
    try testing.expectEqual(@as(u8, 0x05), code[2]); // modrm: rax, [rip+disp32]
}

test "leaRipRel rsi" {
    const code = assemble(struct { fn f(a: *Asm) void { _ = a.leaRipRel(.rsi); } }.f);
    try testing.expectEqual(@as(u8, 0x35), code[2]); // modrm: rsi=6, [rip+disp32] = 00_110_101
}

// ════════════════════════════════════════════════════════════
// Integration: complete function patterns
// ════════════════════════════════════════════════════════════

test "function prologue pattern" {
    try expectBytes(assemble(struct {
        fn f(a: *Asm) void {
            a.pushReg(.rbp);
            a.movReg(.rbp, .rsp);
            a.subRspImm8(32);
        }
    }.f), &.{
        0x55, // push rbp
        0x48, 0x89, 0xE5, // mov rbp, rsp
        0x48, 0x83, 0xEC, 0x20, // sub rsp, 32
    });
}

test "function epilogue pattern" {
    try expectBytes(assemble(struct {
        fn f(a: *Asm) void {
            a.movReg(.rsp, .rbp);
            a.popReg(.rbp);
            a.ret();
        }
    }.f), &.{
        0x48, 0x89, 0xEC, // mov rsp, rbp
        0x5D, // pop rbp
        0xC3, // ret
    });
}

test "exit(0) syscall" {
    try expectBytes(assemble(struct {
        fn f(a: *Asm) void {
            a.movImm64(.rax, 60);
            a.movImm64(.rdi, 0);
            a.syscall();
        }
    }.f), &.{
        0x48, 0xB8, 60, 0, 0, 0, 0, 0, 0, 0, // mov rax, 60
        0x48, 0xBF, 0, 0, 0, 0, 0, 0, 0, 0, // mov rdi, 0
        0x0F, 0x05, // syscall
    });
}

test "comparison and setcc pattern" {
    try expectBytes(assemble(struct {
        fn f(a: *Asm) void {
            a.cmpReg(.rax, .rcx);
            a.setl(.rax);
            a.movzxByte(.rax, .rax);
        }
    }.f), &.{
        0x48, 0x39, 0xC8, // cmp rax, rcx
        0x0F, 0x9C, 0xC0, // setl al
        0x48, 0x0F, 0xB6, 0xC0, // movzx rax, al
    });
}

test "branchless select with cmov" {
    // if rax < rcx { rax = rdx } — branchless
    try expectBytes(assemble(struct {
        fn f(a: *Asm) void {
            a.cmpReg(.rax, .rcx);
            a.cmovl(.rax, .rdx);
        }
    }.f), &.{
        0x48, 0x39, 0xC8, // cmp rax, rcx
        0x48, 0x0F, 0x4C, 0xC2, // cmovl rax, rdx
    });
}

test "while loop pattern: test + je + body + jmp back" {
    var a = Asm.init(std.heap.page_allocator);
    // while rax != 0 { rax = rax - 1 }
    const loop_top = a.offset();
    a.testReg(.rax); // test rax, rax
    const exit = a.jeRel32(); // je exit
    a.movImm64(.rcx, 1); // body: rcx = 1
    a.subReg(.rax, .rcx); // rax -= rcx
    _ = a.jmpRel32(); // jmp loop_top
    // Patch backward jump
    const back_from = a.offset();
    const rel_back: i32 = @intCast(@as(i64, @intCast(loop_top)) - @as(i64, @intCast(back_from)));
    const back_bytes: [4]u8 = @bitCast(rel_back);
    a.code.items[back_from - 4] = back_bytes[0];
    a.code.items[back_from - 3] = back_bytes[1];
    a.code.items[back_from - 2] = back_bytes[2];
    a.code.items[back_from - 1] = back_bytes[3];
    a.patchRel32(exit); // patch forward jump
    // Verify structure
    try testing.expect(a.code.items.len > 0);
    try testing.expectEqual(@as(u8, 0x48), a.code.items[0]); // REX.W for test
    try testing.expectEqual(@as(u8, 0x85), a.code.items[1]); // TEST opcode
}

test "callee-save register preservation" {
    try expectBytes(assemble(struct {
        fn f(a: *Asm) void {
            // Save callee-saved registers
            a.pushReg(.rbx);
            a.pushReg(.r12);
            a.pushReg(.r13);
            a.pushReg(.r14);
            a.pushReg(.r15);
            // ... function body ...
            a.nop();
            // Restore in reverse order
            a.popReg(.r15);
            a.popReg(.r14);
            a.popReg(.r13);
            a.popReg(.r12);
            a.popReg(.rbx);
        }
    }.f), &.{
        0x53, // push rbx
        0x41, 0x54, // push r12
        0x41, 0x55, // push r13
        0x41, 0x56, // push r14
        0x41, 0x57, // push r15
        0x90, // nop
        0x41, 0x5F, // pop r15
        0x41, 0x5E, // pop r14
        0x41, 0x5D, // pop r13
        0x41, 0x5C, // pop r12
        0x5B, // pop rbx
    });
}

test "function call with 3 args pattern" {
    // Verve calling convention: args in rdi, rsi, rdx (System V AMD64)
    var a = Asm.init(std.heap.page_allocator);
    a.movImm64(.rdi, 1); // arg0
    a.movImm64(.rsi, 2); // arg1
    a.movImm64(.rdx, 3); // arg2
    const patch = a.callRel32(); // call target
    _ = patch;
    // Verify first instruction
    try testing.expectEqual(@as(u8, 0x48), a.code.items[0]);
    try testing.expectEqual(@as(u8, 0xBF), a.code.items[1]); // mov rdi
    // Verify call opcode
    try testing.expectEqual(@as(u8, 0xE8), a.code.items[30]); // call
}
