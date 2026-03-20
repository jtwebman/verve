const std = @import("std");
const elf = @import("elf.zig");
const x86 = @import("x86.zig");
const testing = std.testing;
const alloc = std.heap.page_allocator;

fn readU16(bytes: []const u8, offset: usize) u16 { return @bitCast(bytes[offset..][0..2].*); }
fn readU32(bytes: []const u8, offset: usize) u32 { return @bitCast(bytes[offset..][0..4].*); }
fn readU64(bytes: []const u8, offset: usize) u64 { return @bitCast(bytes[offset..][0..8].*); }

// ════════════════════════════════════════════════════════════
// Layout
// ════════════════════════════════════════════════════════════

test "layout: headers = 64 + 56 = 120" {
    const layout = elf.computeLayout(0, 0);
    try testing.expectEqual(@as(u64, 120), layout.headers_size);
}

test "layout: code offset 16-byte aligned" {
    const layout = elf.computeLayout(100, 0);
    try testing.expectEqual(@as(u64, 0), layout.code_offset % 16);
}

test "layout: code vaddr = BASE + code_offset" {
    const layout = elf.computeLayout(100, 0);
    try testing.expectEqual(elf.BASE_ADDR + layout.code_offset, layout.code_vaddr);
}

test "layout: rodata after code, 16-byte aligned" {
    const layout = elf.computeLayout(100, 50);
    try testing.expect(layout.rodata_offset >= layout.code_offset + 100);
    try testing.expectEqual(@as(u64, 0), layout.rodata_offset % 16);
}

// ════════════════════════════════════════════════════════════
// ELF header
// ════════════════════════════════════════════════════════════

test "elf: magic bytes" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqualSlices(u8, "\x7fELF", bytes[0..4]);
}

test "elf: class 64-bit" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u8, 2), bytes[4]);
}

test "elf: little-endian" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u8, 1), bytes[5]);
}

test "elf: type executable" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u16, 2), readU16(bytes, 16));
}

test "elf: machine x86_64" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u16, 62), readU16(bytes, 18));
}

test "elf: entry point matches code vaddr" {
    const code = &[_]u8{ 0x90, 0xC3 };
    const bytes = try elf.buildElf(alloc, code, "");
    const layout = elf.computeLayout(code.len, 0);
    try testing.expectEqual(layout.code_vaddr, readU64(bytes, 24));
}

test "elf: phoff = 64" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u64, 64), readU64(bytes, 32));
}

test "elf: single program header" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u16, 1), readU16(bytes, 56));
}

// ════════════════════════════════════════════════════════════
// Program header
// ════════════════════════════════════════════════════════════

test "phdr: type PT_LOAD" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u32, 1), readU32(bytes, 64));
}

test "phdr: flags RWX" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u32, 7), readU32(bytes, 68)); // R|W|X
}

test "phdr: offset is 0" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(@as(u64, 0), readU64(bytes, 72));
}

test "phdr: vaddr is BASE_ADDR" {
    const bytes = try elf.buildElf(alloc, &.{0xC3}, "");
    try testing.expectEqual(elf.BASE_ADDR, readU64(bytes, 80));
}

// ════════════════════════════════════════════════════════════
// Code and rodata placement
// ════════════════════════════════════════════════════════════

test "code at correct offset" {
    const code = &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    const bytes = try elf.buildElf(alloc, code, "");
    const offset: usize = @intCast(elf.computeLayout(code.len, 0).code_offset);
    try testing.expectEqualSlices(u8, code, bytes[offset .. offset + code.len]);
}

test "rodata at correct offset" {
    const code = &[_]u8{0xC3};
    const rodata = "Hello!";
    const bytes = try elf.buildElf(alloc, code, rodata);
    const offset: usize = @intCast(elf.computeLayout(code.len, rodata.len).rodata_offset);
    try testing.expectEqualSlices(u8, rodata, bytes[offset .. offset + rodata.len]);
}

test "emit creates file" {
    const path = "/tmp/verve_elf_test_create";
    try elf.emit(alloc, &.{0xC3}, "", path);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    try testing.expect((try file.stat()).size > 0);
    try std.fs.cwd().deleteFile(path);
}

// ════════════════════════════════════════════════════════════
// Integration: assemble → ELF → run → verify exit code
// ════════════════════════════════════════════════════════════

fn runBinary(path: []const u8) !std.process.Child.Term {
    var child = std.process.Child.init(&.{path}, alloc);
    return try child.spawnAndWait();
}

test "run: exit(0)" {
    var a = x86.Asm.init(alloc);
    a.movImm64(.rax, 60);
    a.movImm64(.rdi, 0);
    a.syscall();
    const path = "/tmp/verve_run_exit0";
    try elf.emit(alloc, a.code.items, "", path);
    defer std.fs.cwd().deleteFile(path) catch {};
    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, try runBinary(path));
}

test "run: exit(42)" {
    var a = x86.Asm.init(alloc);
    a.movImm64(.rax, 60);
    a.movImm64(.rdi, 42);
    a.syscall();
    const path = "/tmp/verve_run_exit42";
    try elf.emit(alloc, a.code.items, "", path);
    defer std.fs.cwd().deleteFile(path) catch {};
    try testing.expectEqual(std.process.Child.Term{ .Exited = 42 }, try runBinary(path));
}

test "run: 3 + 4 = 7" {
    var a = x86.Asm.init(alloc);
    a.movImm64(.rax, 3);
    a.movImm64(.rcx, 4);
    a.addReg(.rax, .rcx);
    a.movReg(.rdi, .rax);
    a.movImm64(.rax, 60);
    a.syscall();
    const path = "/tmp/verve_run_add";
    try elf.emit(alloc, a.code.items, "", path);
    defer std.fs.cwd().deleteFile(path) catch {};
    try testing.expectEqual(std.process.Child.Term{ .Exited = 7 }, try runBinary(path));
}

test "run: 10 - 3 = 7" {
    var a = x86.Asm.init(alloc);
    a.movImm64(.rax, 10);
    a.movImm64(.rcx, 3);
    a.subReg(.rax, .rcx);
    a.movReg(.rdi, .rax);
    a.movImm64(.rax, 60);
    a.syscall();
    const path = "/tmp/verve_run_sub";
    try elf.emit(alloc, a.code.items, "", path);
    defer std.fs.cwd().deleteFile(path) catch {};
    try testing.expectEqual(std.process.Child.Term{ .Exited = 7 }, try runBinary(path));
}

test "run: 6 * 7 = 42" {
    var a = x86.Asm.init(alloc);
    a.movImm64(.rax, 6);
    a.movImm64(.rcx, 7);
    a.imulReg(.rax, .rcx);
    a.movReg(.rdi, .rax);
    a.movImm64(.rax, 60);
    a.syscall();
    const path = "/tmp/verve_run_mul";
    try elf.emit(alloc, a.code.items, "", path);
    defer std.fs.cwd().deleteFile(path) catch {};
    try testing.expectEqual(std.process.Child.Term{ .Exited = 42 }, try runBinary(path));
}

test "run: 42 / 6 = 7" {
    var a = x86.Asm.init(alloc);
    a.movImm64(.rax, 42);
    a.movImm64(.rcx, 6);
    a.cqo();
    a.idivReg(.rcx);
    a.movReg(.rdi, .rax);
    a.movImm64(.rax, 60);
    a.syscall();
    const path = "/tmp/verve_run_div";
    try elf.emit(alloc, a.code.items, "", path);
    defer std.fs.cwd().deleteFile(path) catch {};
    try testing.expectEqual(std.process.Child.Term{ .Exited = 7 }, try runBinary(path));
}

test "run: 5 < 10 = true (1)" {
    var a = x86.Asm.init(alloc);
    a.movImm64(.rax, 5);
    a.movImm64(.rcx, 10);
    a.cmpReg(.rax, .rcx);
    a.setl(.rax);
    a.movzxByte(.rax, .rax);
    a.movReg(.rdi, .rax);
    a.movImm64(.rax, 60);
    a.syscall();
    const path = "/tmp/verve_run_cmp";
    try elf.emit(alloc, a.code.items, "", path);
    defer std.fs.cwd().deleteFile(path) catch {};
    try testing.expectEqual(std.process.Child.Term{ .Exited = 1 }, try runBinary(path));
}

test "run: call function and return" {
    var a = x86.Asm.init(alloc);
    // call fn
    const call_patch = a.callRel32();
    // after return: exit(rax)
    a.movReg(.rdi, .rax);
    a.movImm64(.rax, 60);
    a.syscall();
    // fn: return 42
    const fn_offset = a.offset();
    a.movImm64(.rax, 42);
    a.ret();
    a.patchRel32At(call_patch, fn_offset);

    const path = "/tmp/verve_run_call";
    try elf.emit(alloc, a.code.items, "", path);
    defer std.fs.cwd().deleteFile(path) catch {};
    try testing.expectEqual(std.process.Child.Term{ .Exited = 42 }, try runBinary(path));
}

test "run: write hello to stdout" {
    var a = x86.Asm.init(alloc);
    const msg = "Hello from Verve!\n";
    // write(1, msg, len)
    a.movImm64(.rax, 1);
    a.movImm64(.rdi, 1);
    a.movImm64(.rsi, 0); // placeholder for rodata addr
    const rsi_patch = a.code.items.len - 8;
    a.movImm64(.rdx, @intCast(msg.len));
    a.syscall();
    // exit(0)
    a.movImm64(.rax, 60);
    a.movImm64(.rdi, 0);
    a.syscall();

    // Patch rsi with actual rodata address
    const layout = elf.computeLayout(a.code.items.len, msg.len);
    const addr_bytes: [8]u8 = @bitCast(layout.rodata_vaddr);
    @memcpy(a.code.items[rsi_patch..][0..8], &addr_bytes);

    const path = "/tmp/verve_run_hello";
    try elf.emit(alloc, a.code.items, msg, path);
    defer std.fs.cwd().deleteFile(path) catch {};

    var child = std.process.Child.init(&.{path}, alloc);
    child.stdout_behavior = .Pipe;
    try child.spawn();
    var buf: [1024]u8 = undefined;
    const n = try child.stdout.?.readAll(&buf);
    const term = try child.wait();
    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, term);
    try testing.expectEqualStrings("Hello from Verve!\n", buf[0..n]);
}
