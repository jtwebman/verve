const std = @import("std");

/// Minimal ELF64 binary emitter for Linux x86_64.
/// Produces a static executable with .text and .rodata sections.

const ELF_MAGIC = "\x7fELF";
const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1; // little-endian
const EV_CURRENT: u8 = 1;
const ELFOSABI_NONE: u8 = 0;
const ET_EXEC: u16 = 2; // executable
const EM_X86_64: u16 = 62;
const PT_LOAD: u32 = 1;
const PF_X: u32 = 1; // execute
const PF_W: u32 = 2; // write
const PF_R: u32 = 4; // read

const BASE_ADDR: u64 = 0x400000;
const ELF_HEADER_SIZE: u64 = 64;
const PHDR_SIZE: u64 = 56;

pub fn emit(alloc: std.mem.Allocator, code: []const u8, rodata: []const u8, output_path: []const u8) !void {
    // Layout:
    // [ELF header][2 program headers][code (page-aligned)][rodata]
    const num_phdrs: u64 = 2;
    const headers_size = ELF_HEADER_SIZE + (num_phdrs * PHDR_SIZE);

    // Align code start to 16 bytes after headers
    const code_offset = alignUp(headers_size, 16);
    const code_size: u64 = @intCast(code.len);

    // Rodata follows code
    const rodata_offset = alignUp(code_offset + code_size, 16);
    const rodata_size: u64 = @intCast(rodata.len);

    const total_size = rodata_offset + rodata_size;

    // Build the file
    var buf = try std.ArrayListUnmanaged(u8).initCapacity(alloc, @intCast(total_size));

    // ── ELF Header (64 bytes) ──────────────────────────────
    buf.appendSliceAssumeCapacity(ELF_MAGIC); // e_ident[0..4]
    buf.appendAssumeCapacity(ELFCLASS64); // e_ident[4]
    buf.appendAssumeCapacity(ELFDATA2LSB); // e_ident[5]
    buf.appendAssumeCapacity(EV_CURRENT); // e_ident[6]
    buf.appendAssumeCapacity(ELFOSABI_NONE); // e_ident[7]
    buf.appendSliceAssumeCapacity(&[_]u8{0} ** 8); // e_ident[8..16] padding

    appendU16(&buf, ET_EXEC); // e_type
    appendU16(&buf, EM_X86_64); // e_machine
    appendU32(&buf, 1); // e_version
    appendU64(&buf, BASE_ADDR + code_offset); // e_entry — start of code
    appendU64(&buf, ELF_HEADER_SIZE); // e_phoff — program headers right after
    appendU64(&buf, 0); // e_shoff — no section headers
    appendU32(&buf, 0); // e_flags
    appendU16(&buf, @intCast(ELF_HEADER_SIZE)); // e_ehsize
    appendU16(&buf, @intCast(PHDR_SIZE)); // e_phentsize
    appendU16(&buf, @intCast(num_phdrs)); // e_phnum
    appendU16(&buf, 0); // e_shentsize
    appendU16(&buf, 0); // e_shnum
    appendU16(&buf, 0); // e_shstrndx

    // ── Program Header 1: code (.text) ─────────────────────
    appendU32(&buf, PT_LOAD); // p_type
    appendU32(&buf, PF_R | PF_X); // p_flags
    appendU64(&buf, code_offset); // p_offset
    appendU64(&buf, BASE_ADDR + code_offset); // p_vaddr
    appendU64(&buf, BASE_ADDR + code_offset); // p_paddr
    appendU64(&buf, code_size); // p_filesz
    appendU64(&buf, code_size); // p_memsz
    appendU64(&buf, 0x1000); // p_align

    // ── Program Header 2: rodata ───────────────────────────
    appendU32(&buf, PT_LOAD); // p_type
    appendU32(&buf, PF_R); // p_flags
    appendU64(&buf, rodata_offset); // p_offset
    appendU64(&buf, BASE_ADDR + rodata_offset); // p_vaddr
    appendU64(&buf, BASE_ADDR + rodata_offset); // p_paddr
    appendU64(&buf, rodata_size); // p_filesz
    appendU64(&buf, rodata_size); // p_memsz
    appendU64(&buf, 0x1000); // p_align

    // ── Padding to code offset ─────────────────────────────
    while (buf.items.len < code_offset) {
        buf.appendAssumeCapacity(0);
    }

    // ── Code ───────────────────────────────────────────────
    buf.appendSliceAssumeCapacity(code);

    // ── Padding to rodata offset ───────────────────────────
    while (buf.items.len < rodata_offset) {
        buf.append(alloc, 0) catch {};
    }

    // ── Rodata ─────────────────────────────────────────────
    buf.appendSlice(alloc, rodata) catch {};

    // ── Write file ─────────────────────────────────────────
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(buf.items);

    // Make executable
    const stat = try file.stat();
    _ = stat;
    try file.chmod(0o755);
}

/// Returns the rodata virtual address for use in code generation
pub fn rodataVaddr(code: []const u8) u64 {
    const headers_size = ELF_HEADER_SIZE + (2 * PHDR_SIZE);
    const code_offset = alignUp(headers_size, 16);
    const code_size: u64 = @intCast(code.len);
    const rodata_offset = alignUp(code_offset + code_size, 16);
    return BASE_ADDR + rodata_offset;
}

pub fn codeVaddr() u64 {
    const headers_size = ELF_HEADER_SIZE + (2 * PHDR_SIZE);
    const code_offset = alignUp(headers_size, 16);
    return BASE_ADDR + code_offset;
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
