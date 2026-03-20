const std = @import("std");

/// Minimal ELF64 binary emitter for Linux x86_64.
/// Produces a static executable with a single PT_LOAD segment.
/// Everything (headers, code, rodata) in one contiguous load.

pub const ELF_MAGIC = "\x7fELF";
pub const ELFCLASS64: u8 = 2;
pub const ELFDATA2LSB: u8 = 1;
pub const EV_CURRENT: u8 = 1;
pub const ELFOSABI_NONE: u8 = 0;
pub const ET_EXEC: u16 = 2;
pub const EM_X86_64: u16 = 62;
pub const PT_LOAD: u32 = 1;
pub const PF_X: u32 = 1;
pub const PF_W: u32 = 2;
pub const PF_R: u32 = 4;

pub const BASE_ADDR: u64 = 0x400000;
pub const ELF_HEADER_SIZE: u64 = 64;
pub const PHDR_SIZE: u64 = 56;

/// Layout information.
pub const Layout = struct {
    headers_size: u64,
    code_offset: u64,
    code_vaddr: u64,
    rodata_offset: u64,
    rodata_vaddr: u64,
    total_size: u64,
};

pub fn computeLayout(code_len: usize, rodata_len: usize) Layout {
    // Single program header
    const headers_size = ELF_HEADER_SIZE + PHDR_SIZE;
    const code_offset = alignUp(headers_size, 16);
    const code_size: u64 = @intCast(code_len);
    const rodata_offset = alignUp(code_offset + code_size, 16);
    const rodata_size: u64 = @intCast(rodata_len);
    return .{
        .headers_size = headers_size,
        .code_offset = code_offset,
        .code_vaddr = BASE_ADDR + code_offset,
        .rodata_offset = rodata_offset,
        .rodata_vaddr = BASE_ADDR + rodata_offset,
        .total_size = if (rodata_size > 0) rodata_offset + rodata_size else code_offset + code_size,
    };
}

/// Build the ELF binary in memory.
pub fn buildElf(alloc: std.mem.Allocator, code: []const u8, rodata: []const u8) ![]u8 {
    const layout = computeLayout(code.len, rodata.len);
    const total: usize = @intCast(layout.total_size);

    var buf = std.ArrayListUnmanaged(u8){};
    try buf.ensureTotalCapacity(alloc, total + 64);

    // ── ELF Header (64 bytes) ──────────────────────────────
    buf.appendSliceAssumeCapacity(ELF_MAGIC);
    buf.appendAssumeCapacity(ELFCLASS64);
    buf.appendAssumeCapacity(ELFDATA2LSB);
    buf.appendAssumeCapacity(EV_CURRENT);
    buf.appendAssumeCapacity(ELFOSABI_NONE);
    buf.appendSliceAssumeCapacity(&[_]u8{0} ** 8);

    appendU16(&buf, ET_EXEC);
    appendU16(&buf, EM_X86_64);
    appendU32(&buf, 1);
    appendU64(&buf, layout.code_vaddr); // e_entry
    appendU64(&buf, ELF_HEADER_SIZE); // e_phoff
    appendU64(&buf, 0); // e_shoff
    appendU32(&buf, 0); // e_flags
    appendU16(&buf, @intCast(ELF_HEADER_SIZE));
    appendU16(&buf, @intCast(PHDR_SIZE));
    appendU16(&buf, 1); // e_phnum = 1 (single segment)
    appendU16(&buf, 0);
    appendU16(&buf, 0);
    appendU16(&buf, 0);

    // ── Single Program Header: load entire file ────────────
    appendU32(&buf, PT_LOAD);
    appendU32(&buf, PF_R | PF_W | PF_X); // RWX for simplicity
    appendU64(&buf, 0); // p_offset = start of file
    appendU64(&buf, BASE_ADDR); // p_vaddr
    appendU64(&buf, BASE_ADDR); // p_paddr
    appendU64(&buf, @intCast(total)); // p_filesz
    appendU64(&buf, @intCast(total)); // p_memsz
    appendU64(&buf, 0x200000); // p_align = 2MB

    // ── Padding to code offset ─────────────────────────────
    while (buf.items.len < layout.code_offset) {
        buf.appendAssumeCapacity(0);
    }

    // ── Code ───────────────────────────────────────────────
    buf.appendSliceAssumeCapacity(code);

    // ── Padding to rodata offset ───────────────────────────
    if (rodata.len > 0) {
        while (buf.items.len < layout.rodata_offset) {
            try buf.append(alloc, 0);
        }
        try buf.appendSlice(alloc, rodata);
    }

    return buf.items;
}

/// Build and write to disk.
pub fn emit(alloc: std.mem.Allocator, code: []const u8, rodata: []const u8, output_path: []const u8) !void {
    const bytes = try buildElf(alloc, code, rodata);
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(bytes);
    try file.chmod(0o755);
}

pub fn rodataVaddr(code: []const u8) u64 {
    return computeLayout(code.len, 0).rodata_vaddr;
}

pub fn codeVaddr() u64 {
    return computeLayout(0, 0).code_vaddr;
}

fn alignUp(val: u64, alignment: u64) u64 {
    return (val + alignment - 1) & ~(alignment - 1);
}

fn appendU16(buf: *std.ArrayListUnmanaged(u8), val: u16) void {
    const bytes: [2]u8 = @bitCast(val);
    buf.appendSliceAssumeCapacity(&bytes);
}

fn appendU32(buf: *std.ArrayListUnmanaged(u8), val: u32) void {
    const bytes: [4]u8 = @bitCast(val);
    buf.appendSliceAssumeCapacity(&bytes);
}

fn appendU64(buf: *std.ArrayListUnmanaged(u8), val: u64) void {
    const bytes: [8]u8 = @bitCast(val);
    buf.appendSliceAssumeCapacity(&bytes);
}
