const std = @import("std");

// ── Sub-modules ─────────────────────────────────────
pub const string = @import("string.zig");
pub const math = @import("math.zig");
pub const checked = @import("checked.zig");
pub const convert = @import("convert.zig");
pub const json = @import("json.zig");
pub const io = @import("io.zig");
pub const tcp = @import("tcp.zig");
pub const http = @import("http.zig");
pub const process = @import("process.zig");
pub const fiber = @import("fiber.zig");
pub const profile = @import("profile.zig");
pub const stringbuilder = @import("stringbuilder.zig");

// ── Constants ──────────────────────────────────────
pub const MAILBOX_BUF_SIZE = 4 * 1024; // 4KB byte ring buffer per process (was 64KB — too large for short-lived processes)
pub const MAX_PROCESSES = 256; // initial capacity, grows dynamically
pub const MAX_WATCHERS = 64;
pub const MAX_INLINE_STRING = 4096; // strings > this use arena reference

/// Message argument type tags for the binary protocol.
pub const ArgType = enum(u8) { int = 0, float = 1, boolean = 2, string = 3, string_ref = 4 };

// ── Initialization ─────────────────────────────────

/// Must be called at program startup. Ignores SIGPIPE so writing to a closed
/// socket returns an error instead of killing the process.
pub fn verve_runtime_init() void {
    // Initialize profiler (enabled via VERVE_PROFILE=1 env var)
    profile.init();

    // Initialize dynamic process table
    process.ensureProcessCapacity(MAX_PROCESSES);

    const act = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &act, null);

    // Dump profile on SIGTERM/SIGINT before exit
    const term_act = std.posix.Sigaction{
        .handler = .{ .handler = handleShutdown },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &term_act, null);
    std.posix.sigaction(std.posix.SIG.INT, &term_act, null);
}

const MAX_SLICE_LEN: usize = 16 * 1024 * 1024; // 16MB — arena max
const MIN_VALID_PTR: usize = 4096;

fn isLikelyValidPtr(ptr_val: usize) bool {
    return ptr_val >= MIN_VALID_PTR;
}

fn isAlignedPtr(ptr_val: usize, alignment: usize) bool {
    return (ptr_val & (alignment - 1)) == 0;
}

pub fn runtimeFail(msg: []const u8) noreturn {
    _ = std.posix.write(std.posix.STDERR_FILENO, msg) catch 0;
    _ = std.posix.write(std.posix.STDERR_FILENO, "\n") catch 0;
    std.process.exit(1);
}

/// Convert (ptr, len) pair back to []const u8 — used at struct boundaries.
pub fn sliceFromPair(ptr_val: usize, len_val: usize) []const u8 {
    if (ptr_val == 0 or len_val == 0) return "";
    if (len_val > MAX_SLICE_LEN) return "";
    if (!isLikelyValidPtr(ptr_val)) return "";
    return @as([*]const u8, @ptrFromInt(ptr_val))[0..len_val];
}

// ── Tagged values (Result<T>) ──────────────────────

pub const Tagged = struct { tag: i64, value: i64 };

pub fn makeTagged(tag: i64, value: i64) usize {
    const mem = arena_alloc(@sizeOf(Tagged)) orelse return 0;
    const t = @as(*Tagged, @ptrCast(@alignCast(mem)));
    t.* = .{ .tag = tag, .value = value };
    return @intFromPtr(t);
}

pub fn getTag(ptr: usize) i64 {
    if (ptr == 0 or !isLikelyValidPtr(ptr) or !isAlignedPtr(ptr, @alignOf(Tagged))) return -1;
    return @as(*const Tagged, @ptrFromInt(ptr)).tag;
}

pub fn getTagValue(ptr: usize) i64 {
    if (ptr == 0 or !isLikelyValidPtr(ptr) or !isAlignedPtr(ptr, @alignOf(Tagged))) return 0;
    return @as(*const Tagged, @ptrFromInt(ptr)).value;
}

/// Store a string (ptr+len) inside a tagged value. The slice metadata is
/// copied into the arena so the caller can later recover it via getTagStr.
pub fn makeTaggedStr(tag: i64, s: []const u8) usize {
    const SliceMeta = struct { ptr: [*]const u8, len: usize };
    const meta_mem = arena_alloc(@sizeOf(SliceMeta)) orelse return 0;
    const meta = @as(*SliceMeta, @ptrCast(@alignCast(meta_mem)));
    meta.* = .{ .ptr = s.ptr, .len = s.len };
    return makeTagged(tag, @intCast(@intFromPtr(meta)));
}

/// Recover a string slice from a tagged value created via makeTaggedStr.
pub fn getTagStr(ptr: usize) []const u8 {
    if (ptr == 0 or !isLikelyValidPtr(ptr)) return "";
    const val = getTagValue(ptr);
    if (val == 0) return "";
    const SliceMeta = struct { ptr: [*]const u8, len: usize };
    const meta_ptr: usize = @intCast(@as(u64, @bitCast(val)));
    if (!isLikelyValidPtr(meta_ptr) or !isAlignedPtr(meta_ptr, @alignOf(SliceMeta))) return "";
    const meta = @as(*const SliceMeta, @ptrFromInt(meta_ptr));
    if (meta.len > MAX_SLICE_LEN) return "";
    if (meta.len == 0) return "";
    const raw_ptr = @intFromPtr(meta.ptr);
    if (!isLikelyValidPtr(raw_ptr)) return "";
    return sliceFromPair(raw_ptr, meta.len);
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

    pub fn tryAppend(self: *List, val: i64) !void {
        if (self.cap == 0 or !isLikelyValidPtr(@intFromPtr(self.items))) return error.ListUninitialized;
        if (self.len >= self.cap) return error.ListCapacityExceeded;
        const idx: usize = @intCast(@as(u64, @bitCast(self.len)));
        self.items[idx] = val;
        self.len += 1;
    }

    pub fn append(self: *List, val: i64) void {
        self.tryAppend(val) catch |err| switch (err) {
            error.ListUninitialized => runtimeFail("Verve runtime error: list append on uninitialized list"),
            error.ListCapacityExceeded => runtimeFail("Verve runtime error: list capacity exceeded"),
        };
    }

    pub fn tryAppendPtr(self: *List, val: usize) !void {
        if (self.cap == 0 or !isLikelyValidPtr(@intFromPtr(self.items))) return error.ListUninitialized;
        if (self.len >= self.cap) return error.ListCapacityExceeded;
        const idx: usize = @intCast(@as(u64, @bitCast(self.len)));
        self.items[idx] = @intCast(val);
        self.len += 1;
    }

    pub fn appendPtr(self: *List, val: usize) void {
        self.tryAppendPtr(val) catch |err| switch (err) {
            error.ListUninitialized => runtimeFail("Verve runtime error: list append on uninitialized list"),
            error.ListCapacityExceeded => runtimeFail("Verve runtime error: list capacity exceeded"),
        };
    }

    pub fn get(self: *const List, idx: i64) i64 {
        if (idx < 0 or idx >= self.len) return @import("checked.zig").POISON_OUT_OF_BOUNDS;
        return self.items[@intCast(@as(u64, @bitCast(idx)))];
    }
};

var empty_list_storage = List{
    .items = undefined,
    .len = 0,
    .cap = 0,
};

pub fn emptyListPtr() usize {
    return @intFromPtr(&empty_list_storage);
}

pub fn emptyListI64() i64 {
    return @intCast(emptyListPtr());
}

pub fn allocList() usize {
    const raw = arena_alloc(@sizeOf(List)) orelse return emptyListPtr();
    const list = @as(*List, @ptrCast(@alignCast(raw)));
    list.* = List.init();
    if (list.cap == 0) return emptyListPtr();
    return @intFromPtr(list);
}

// ── Env ────────────────────────────────────────────

pub fn env_get(name: []const u8) []const u8 {
    const val = std.posix.getenv(name) orelse return "";
    return val;
}

fn envWriteStderr(s: []const u8) void {
    _ = std.posix.write(std.posix.STDERR_FILENO, s) catch 0;
}

fn envDie(name: []const u8, expected: []const u8, got: []const u8) noreturn {
    envWriteStderr("Verve: env var '");
    envWriteStderr(name);
    envWriteStderr("' expected ");
    envWriteStderr(expected);
    envWriteStderr(", got '");
    envWriteStderr(got);
    envWriteStderr("'\n");
    std.process.exit(1);
}

fn envMissing(name: []const u8, expected: []const u8) noreturn {
    envWriteStderr("Verve: env var '");
    envWriteStderr(name);
    envWriteStderr("' (");
    envWriteStderr(expected);
    envWriteStderr(") is required but not set\n");
    std.process.exit(1);
}

pub fn env_int(name: []const u8, default: i64) i64 {
    const val = std.posix.getenv(name) orelse return default;
    if (val.len == 0) return default;
    return std.fmt.parseInt(i64, val, 10) catch envDie(name, "int", val);
}

pub fn env_int_required(name: []const u8) i64 {
    const val = std.posix.getenv(name) orelse envMissing(name, "int");
    if (val.len == 0) envMissing(name, "int");
    return std.fmt.parseInt(i64, val, 10) catch envDie(name, "int", val);
}

pub fn env_float(name: []const u8, default: f64) f64 {
    const val = std.posix.getenv(name) orelse return default;
    if (val.len == 0) return default;
    return std.fmt.parseFloat(f64, val) catch envDie(name, "float", val);
}

pub fn env_float_required(name: []const u8) f64 {
    const val = std.posix.getenv(name) orelse envMissing(name, "float");
    if (val.len == 0) envMissing(name, "float");
    return std.fmt.parseFloat(f64, val) catch envDie(name, "float", val);
}

pub fn env_bool(name: []const u8, default: bool) bool {
    const val = std.posix.getenv(name) orelse return default;
    if (val.len == 0) return default;
    return parseBoolEnv(name, val);
}

pub fn env_bool_required(name: []const u8) bool {
    const val = std.posix.getenv(name) orelse envMissing(name, "bool");
    if (val.len == 0) envMissing(name, "bool");
    return parseBoolEnv(name, val);
}

fn parseBoolEnv(name: []const u8, val: []const u8) bool {
    // true: "true" (any case), "t"/"T", "1"
    if (std.mem.eql(u8, val, "1")) return true;
    if (val.len == 1 and (val[0] == 't' or val[0] == 'T')) return true;
    if (val.len == 4 and
        (val[0] == 't' or val[0] == 'T') and
        (val[1] == 'r' or val[1] == 'R') and
        (val[2] == 'u' or val[2] == 'U') and
        (val[3] == 'e' or val[3] == 'E'))
        return true;
    // false: "false" (any case), "f"/"F", "0"
    if (std.mem.eql(u8, val, "0")) return false;
    if (val.len == 1 and (val[0] == 'f' or val[0] == 'F')) return false;
    if (val.len == 5 and
        (val[0] == 'f' or val[0] == 'F') and
        (val[1] == 'a' or val[1] == 'A') and
        (val[2] == 'l' or val[2] == 'L') and
        (val[3] == 's' or val[3] == 'S') and
        (val[4] == 'e' or val[4] == 'E'))
        return false;
    envDie(name, "bool (true/false/t/f/1/0)", val);
}

pub fn env_string(name: []const u8, default: []const u8) []const u8 {
    const val = std.posix.getenv(name) orelse return default;
    if (val.len == 0) return default;
    return val;
}

pub fn env_string_required(name: []const u8) []const u8 {
    const val = std.posix.getenv(name) orelse envMissing(name, "string");
    if (val.len == 0) envMissing(name, "string");
    return val;
}

// ── System ─────────────────────────────────────────

fn handleShutdown(_: i32) callconv(.c) void {
    profile.dump();
    std.process.exit(0);
}

pub fn system_exit(code: i64) noreturn {
    profile.dump();
    std.process.exit(@truncate(@as(u64, @bitCast(code))));
}

pub fn system_time_ms() i64 {
    return @intCast(@divFloor(std.time.milliTimestamp(), 1));
}

// ── Testing ────────────────────────────────────────

pub var assert_fail_count: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);

/// Check an assertion. If false, increment fail count and print failure.
pub fn assert_check(cond: i64) void {
    if (cond == 0) {
        _ = assert_fail_count.fetchAdd(1, .monotonic);
        _ = std.posix.write(std.posix.STDERR_FILENO, "ASSERT FAILED\n") catch 0;
    }
}

// ── Arena allocator ────────────────────────────────

const ARENA_PAGE_SIZE = 64 * 1024; // 64KB per page
const ARENA_MAX_PAGES = 256; // 16MB max per arena
pub const ARENA_MAX_BYTES = ARENA_PAGE_SIZE * ARENA_MAX_PAGES;

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
    if (process.current_process_id > 0 and process.pidValid(process.current_process_id)) {
        const idx = process.pidx(process.current_process_id);
        return process.process_table[idx].arena();
    }
    return &global_arena;
}

/// Allocate from the current arena. Drop-in replacement for page_allocator.alloc.
pub fn arena_alloc(size: usize) ?[*]u8 {
    return currentArena().alloc(size);
}

pub fn arena_is_exhausted() bool {
    const arena = currentArena();
    return arena.page_count >= ARENA_MAX_PAGES and arena.offset >= ARENA_PAGE_SIZE;
}

// ── Tests ─────────────────────────────────────────

test "list tryAppend rejects capacity overflow" {
    var list = List.init();
    for (0..256) |i| {
        try list.tryAppend(@intCast(i));
    }
    try std.testing.expectEqual(@as(i64, 256), list.len);
    try std.testing.expectError(error.ListCapacityExceeded, list.tryAppend(999));
}

test "list tryAppendPtr rejects capacity overflow" {
    var list = List.init();
    for (0..256) |i| {
        try list.tryAppendPtr(i);
    }
    try std.testing.expectEqual(@as(i64, 256), list.len);
    try std.testing.expectError(error.ListCapacityExceeded, list.tryAppendPtr(999));
}

test "list tryAppend rejects uninitialized list" {
    var list = List{ .items = undefined, .len = 0, .cap = 0 };
    try std.testing.expectError(error.ListUninitialized, list.tryAppend(1));
}

test "list tryAppendPtr rejects uninitialized list" {
    var list = List{ .items = undefined, .len = 0, .cap = 0 };
    try std.testing.expectError(error.ListUninitialized, list.tryAppendPtr(1));
}

test "list get out of bounds returns poison" {
    var list = List.init();
    try list.tryAppend(42);
    // Valid access
    try std.testing.expectEqual(@as(i64, 42), list.get(0));
    // Negative index
    try std.testing.expectEqual(@import("checked.zig").POISON_OUT_OF_BOUNDS, list.get(-1));
    // Past end
    try std.testing.expectEqual(@import("checked.zig").POISON_OUT_OF_BOUNDS, list.get(1));
    try std.testing.expectEqual(@import("checked.zig").POISON_OUT_OF_BOUNDS, list.get(100));
}

test "sliceFromPair null ptr returns empty" {
    const s = sliceFromPair(0, 10);
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "sliceFromPair zero len returns empty" {
    const s = sliceFromPair(0xDEAD, 0);
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "sliceFromPair huge len returns empty" {
    const s = sliceFromPair(0xDEAD, MAX_SLICE_LEN + 1);
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "sliceFromPair low ptr returns empty" {
    const s = sliceFromPair(8, 4);
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "getTagStr invalid outer ptr returns empty" {
    const s = getTagStr(8);
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "getTagStr invalid metadata ptr returns empty" {
    const tagged = makeTagged(0, 8);
    const s = getTagStr(tagged);
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "getTagStr huge metadata len returns empty" {
    const SliceMeta = struct { ptr: [*]const u8, len: usize };
    const raw = arena_alloc(@sizeOf(SliceMeta)) orelse return error.OutOfMemory;
    const meta = @as(*SliceMeta, @ptrCast(@alignCast(raw)));
    meta.* = .{ .ptr = "abc".ptr, .len = MAX_SLICE_LEN + 1 };
    const tagged = makeTagged(0, @intCast(@intFromPtr(meta)));
    const s = getTagStr(tagged);
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "getTagStr roundtrip returns original string" {
    const tagged = makeTaggedStr(0, "hello");
    const s = getTagStr(tagged);
    try std.testing.expectEqualStrings("hello", s);
}

test "arena alloc stops cleanly at configured max" {
    var arena = Arena{};
    var pages: usize = 0;
    while (pages < ARENA_MAX_PAGES) : (pages += 1) {
        const mem = arena.alloc(ARENA_PAGE_SIZE) orelse return error.TestUnexpectedResult;
        try std.testing.expect(@intFromPtr(mem) != 0);
    }
    try std.testing.expectEqual(@as(usize, ARENA_MAX_BYTES), arena.total_allocated);
    try std.testing.expect(arena.alloc(8) == null);
    arena.freeAll();
}

test "slice and tagged string helpers survive randomized metadata" {
    var prng = std.Random.DefaultPrng.init(0xC0FFEE);
    const random = prng.random();
    const source = "hello";
    const SliceMeta = struct { ptr: [*]const u8, len: usize };

    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const ptr_val = if (random.boolean()) @intFromPtr(source.ptr) else random.int(usize);
        const len_val = random.intRangeAtMost(usize, 0, MAX_SLICE_LEN + 32);
        const s = sliceFromPair(ptr_val, len_val);
        try std.testing.expect(s.len <= MAX_SLICE_LEN);

        const raw = arena_alloc(@sizeOf(SliceMeta)) orelse return error.OutOfMemory;
        const meta = @as(*SliceMeta, @ptrCast(@alignCast(raw)));
        meta.* = .{
            .ptr = if (random.boolean()) source.ptr else @ptrFromInt(@max(@as(usize, 4096), random.int(usize))),
            .len = random.intRangeAtMost(usize, 0, MAX_SLICE_LEN + 32),
        };
        const tagged = makeTagged(0, @intCast(@intFromPtr(meta)));
        const recovered = getTagStr(tagged);
        try std.testing.expect(recovered.len <= MAX_SLICE_LEN);
    }
}
