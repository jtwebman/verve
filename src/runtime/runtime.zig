const std = @import("std");

// ── Sub-modules ─────────────────────────────────────
pub const string = @import("string.zig");
pub const math = @import("math.zig");
pub const json = @import("json.zig");
pub const net = @import("net.zig");
pub const process = @import("process.zig");

// ── Constants ──────────────────────────────────────
pub const MAILBOX_BUF_SIZE = 64 * 1024; // 64KB byte ring buffer per process
pub const MAX_PROCESSES = 256; // initial capacity, grows dynamically
pub const MAX_WATCHERS = 64;
pub const MAX_INLINE_STRING = 4096; // strings > this use arena reference

/// Message argument type tags for the binary protocol.
pub const ArgType = enum(u8) { int = 0, float = 1, boolean = 2, string = 3, string_ref = 4 };

// HTTP limits (sane defaults, engineers can recompile with different values)
pub const HTTP_MAX_HEADER_SIZE = 8 * 1024; // 8KB per header section
pub const HTTP_MAX_BODY_SIZE = 1024 * 1024; // 1MB request body
pub const HTTP_MAX_URI_SIZE = 8 * 1024; // 8KB URI length
pub const HTTP_MAX_METHOD_SIZE = 16; // longest standard method

// ── Initialization ─────────────────────────────────

/// Must be called at program startup. Ignores SIGPIPE so writing to a closed
/// socket returns an error instead of killing the process.
pub fn verve_runtime_init() void {
    // Initialize dynamic process table
    process.ensureProcessCapacity(MAX_PROCESSES);

    const act = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &act, null);
}

// ── IO helpers ─────────────────────────────────────

pub fn verve_write(fd: i64, s: []const u8) void {
    _ = fd;
    _ = std.posix.write(std.posix.STDOUT_FILENO, s) catch 0;
}

pub fn verve_write_int(fd: i64, val: i64) void {
    _ = fd;
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return;
    _ = std.posix.write(std.posix.STDOUT_FILENO, s) catch 0;
}

pub fn verve_write_float(fd: i64, val: i64) void {
    _ = fd;
    var buf: [64]u8 = undefined;
    const f: f64 = @bitCast(val);
    const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return;
    _ = std.posix.write(std.posix.STDOUT_FILENO, s) catch 0;
}

pub fn fileOpen(path: []const u8) i64 {
    const data = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 10 * 1024 * 1024) catch return makeTagged(1, 0);
    const stream_mem = arena_alloc(3 * @sizeOf(i64)) orelse return makeTagged(1, 0);
    const stream = @as([*]i64, @ptrCast(@alignCast(stream_mem)));
    stream[0] = @intCast(@intFromPtr(data.ptr));
    stream[1] = @intCast(data.len);
    stream[2] = 0;
    return makeTagged(0, @intCast(@intFromPtr(stream)));
}

pub fn streamReadAll(stream_ptr: i64) []const u8 {
    const s = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(stream_ptr))))));
    const ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(s[0]))))));
    const len: usize = @intCast(@as(u64, @bitCast(s[1])));
    return ptr[0..len];
}

/// Convert i64 pair (ptr, len) back to []const u8 — used at struct boundaries.
pub fn sliceFromPair(ptr_val: i64, len_val: i64) []const u8 {
    if (ptr_val == 0) return "";
    const p = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr_val))))));
    const l: usize = @intCast(@as(u64, @bitCast(len_val)));
    return p[0..l];
}

// ── Tagged values (Result<T>) ──────────────────────

pub const Tagged = struct { tag: i64, value: i64 };

pub fn makeTagged(tag: i64, value: i64) i64 {
    const mem = arena_alloc(@sizeOf(Tagged)) orelse return 0;
    const t = @as(*Tagged, @ptrCast(@alignCast(mem)));
    t.* = .{ .tag = tag, .value = value };
    return @intCast(@intFromPtr(t));
}

pub fn getTag(ptr: i64) i64 {
    if (ptr == 0) return -1;
    return @as(*const Tagged, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr)))))).tag;
}

pub fn getTagValue(ptr: i64) i64 {
    if (ptr == 0) return 0;
    return @as(*const Tagged, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr)))))).value;
}

// ── Collections ────────────────────────────────────

pub const List = struct {
    items: [*]i64,
    len: i64,
    cap: i64,

    pub fn init() List {
        const raw = arena_alloc(256 * @sizeOf(i64)) orelse return .{ .items = undefined, .len = 0, .cap = 0 };
        const mem = @as([*]i64, @ptrCast(@alignCast(raw)));
        return .{ .items = mem, .len = 0, .cap = 256 };
    }

    pub fn append(self: *List, val: i64) void {
        const idx: usize = @intCast(@as(u64, @bitCast(self.len)));
        self.items[idx] = val;
        self.len += 1;
    }

    pub fn get(self: *const List, idx: i64) i64 {
        return self.items[@intCast(@as(u64, @bitCast(idx)))];
    }
};

// ── Env ────────────────────────────────────────────

pub fn env_get(name: []const u8) []const u8 {
    const val = std.posix.getenv(name) orelse return "";
    return val;
}

// ── System ─────────────────────────────────────────

pub fn system_exit(code: i64) noreturn {
    std.process.exit(@intCast(@as(u64, @bitCast(code))));
}

pub fn system_time_ms() i64 {
    return @intCast(@divFloor(std.time.milliTimestamp(), 1));
}

// ── Testing ────────────────────────────────────────

pub var assert_fail_count: i64 = 0;

/// Check an assertion. If false, increment fail count and print failure.
pub fn assert_check(cond: i64) void {
    if (cond == 0) {
        assert_fail_count += 1;
        _ = std.posix.write(std.posix.STDERR_FILENO, "ASSERT FAILED\n") catch 0;
    }
}

// ── Arena allocator ────────────────────────────────

const ARENA_PAGE_SIZE = 64 * 1024; // 64KB per page
const ARENA_MAX_PAGES = 256; // 16MB max per arena

pub const Arena = struct {
    pages: [ARENA_MAX_PAGES]?[*]align(8) u8 = .{null} ** ARENA_MAX_PAGES,
    page_count: usize = 0,
    offset: usize = 0,
    total_allocated: usize = 0,

    /// Allocate `size` bytes from this arena. Returns null on failure.
    pub fn alloc(self: *Arena, size: usize) ?[*]u8 {
        // Align to 8 bytes
        const aligned = (size + 7) & ~@as(usize, 7);

        // Try current page
        if (self.page_count > 0 and self.offset + aligned <= ARENA_PAGE_SIZE) {
            const page = self.pages[self.page_count - 1] orelse return null;
            const ptr = page + self.offset;
            self.offset += aligned;
            self.total_allocated += aligned;
            return ptr;
        }

        // Need a new page
        if (self.page_count >= ARENA_MAX_PAGES) return null;
        const new_page = std.heap.page_allocator.alignedAlloc(u8, .@"8", ARENA_PAGE_SIZE) catch return null;
        self.pages[self.page_count] = new_page.ptr;
        self.page_count += 1;
        self.offset = aligned;
        self.total_allocated += aligned;
        return new_page.ptr;
    }

    /// Free all pages. After this, the arena is empty and reusable.
    pub fn freeAll(self: *Arena) void {
        for (0..self.page_count) |i| {
            if (self.pages[i]) |page| {
                std.heap.page_allocator.free(@as([*]u8, @ptrCast(page))[0..ARENA_PAGE_SIZE]);
                self.pages[i] = null;
            }
        }
        self.page_count = 0;
        self.offset = 0;
        self.total_allocated = 0;
    }
};

/// Global arena for non-process code (module main).
var global_arena: Arena = .{};

/// Get the current arena: process-local if in a process, global otherwise.
pub fn currentArena() *Arena {
    if (process.current_process_id > 0) {
        const idx = process.pidx(process.current_process_id);
        if (idx < process.process_table.len) return &process.process_table[idx].arena;
    }
    return &global_arena;
}

/// Allocate from the current arena. Drop-in replacement for page_allocator.alloc.
pub fn arena_alloc(size: usize) ?[*]u8 {
    return currentArena().alloc(size);
}
