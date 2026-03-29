const std = @import("std");

// ── Runtime profiler ──────────────────────────────
// Zero-cost when disabled. Enable at runtime: VERVE_PROFILE=1
// Tracks cumulative time in each phase of request handling.
// Prints summary on System.exit().

pub const Phase = enum(usize) {
    accept = 0,
    spawn = 1,
    drain = 2,
    read = 3,
    write = 4,
    close = 5,
    alloc = 6,
    parse_http = 7,
    build_response = 8,

    const count = 9;
};

const phase_names = [Phase.count][]const u8{
    "accept",
    "spawn",
    "drain",
    "read",
    "write",
    "close",
    "alloc",
    "parse_http",
    "build_resp",
};

var totals: [Phase.count]std.atomic.Value(u64) = .{std.atomic.Value(u64).init(0)} ** Phase.count;
var counts: [Phase.count]std.atomic.Value(u64) = .{std.atomic.Value(u64).init(0)} ** Phase.count;
var enabled: bool = false;

pub fn init() void {
    enabled = std.posix.getenv("VERVE_PROFILE") != null;
}

pub fn isEnabled() bool {
    return enabled;
}

pub inline fn begin() ?std.time.Timer {
    if (!enabled) return null;
    return std.time.Timer.start() catch null;
}

pub inline fn end(phase: Phase, timer_opt: ?std.time.Timer) void {
    var t = timer_opt orelse return;
    const elapsed = t.read();
    _ = totals[@intFromEnum(phase)].fetchAdd(elapsed, .monotonic);
    _ = counts[@intFromEnum(phase)].fetchAdd(1, .monotonic);
}

fn w(s: []const u8) void {
    _ = std.posix.write(std.posix.STDERR_FILENO, s) catch 0;
}

fn wFmt(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    w(s);
}

pub fn dump() void {
    if (!enabled) return;
    w("\n=== Verve Runtime Profile ===\n");
    wFmt("{s:<14} {s:>10} {s:>10} {s:>10}\n", .{ "phase", "total_ms", "calls", "avg_us" });
    w("───────────── ────────── ────────── ──────────\n");
    var grand_total: u64 = 0;
    for (0..Phase.count) |i| {
        const cnt = counts[i].load(.monotonic);
        const tot = totals[i].load(.monotonic);
        if (cnt == 0) continue;
        const total_us = tot / 1000;
        const total_ms = total_us / 1000;
        const frac_ms = (total_us % 1000) / 10;
        const avg_us = total_us / cnt;
        grand_total += tot;
        wFmt("{s:<14} {d:>7}.{d:0>2}ms {d:>10} {d:>8}us\n", .{ phase_names[i], total_ms, frac_ms, cnt, avg_us });
    }
    const gt_us = grand_total / 1000;
    const gt_ms = gt_us / 1000;
    const gt_frac = (gt_us % 1000) / 10;
    wFmt("{s:<14} {d:>7}.{d:0>2}ms\n", .{ "TOTAL", gt_ms, gt_frac });
}
