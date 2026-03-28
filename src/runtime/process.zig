const std = @import("std");
const rt = @import("runtime.zig");

// ── Process runtime ────────────────────────────────

/// Byte ring buffer mailbox. Messages are variable-size binary-encoded byte sequences.
/// Format per message: [msg_len: u16][handler_id: u8][param_count: u8][params...]
/// The msg_len prefix allows popping without decoding the full message.
pub const Mailbox = struct {
    buf: [rt.MAILBOX_BUF_SIZE]u8 = undefined,
    head: usize = 0,
    used: usize = 0, // bytes used in buffer
    count: usize = 0, // number of messages
    reply_slot: ?*i64 = null, // for synchronous send

    /// Push a message (raw bytes) into the mailbox. Returns false if no room.
    pub fn push(self: *Mailbox, msg: [*]const u8, msg_len: usize) bool {
        const total = msg_len + 2; // 2-byte length prefix
        if (self.used + total > rt.MAILBOX_BUF_SIZE) return false;
        const write_pos = (self.head + self.used) % rt.MAILBOX_BUF_SIZE;
        // Write length prefix (little-endian u16)
        const len_u16: u16 = @intCast(msg_len);
        self.buf[write_pos % rt.MAILBOX_BUF_SIZE] = @truncate(len_u16);
        self.buf[(write_pos + 1) % rt.MAILBOX_BUF_SIZE] = @truncate(len_u16 >> 8);
        // Write message bytes (handle wrap-around)
        for (0..msg_len) |i| {
            self.buf[(write_pos + 2 + i) % rt.MAILBOX_BUF_SIZE] = msg[i];
        }
        self.used += total;
        self.count += 1;
        return true;
    }

    /// Pop a message from the mailbox. Returns slice pointing into a provided buffer.
    /// Caller provides a scratch buffer to copy the message into (for wrap-around safety).
    pub fn pop(self: *Mailbox, out_buf: []u8) ?[]const u8 {
        if (self.count == 0) return null;
        // Read length prefix
        const lo: u16 = self.buf[self.head % rt.MAILBOX_BUF_SIZE];
        const hi: u16 = self.buf[(self.head + 1) % rt.MAILBOX_BUF_SIZE];
        const msg_len: usize = lo | (hi << 8);
        // Copy message into out_buf (handles ring buffer wrap-around)
        const capped = @min(msg_len, out_buf.len);
        for (0..capped) |i| {
            out_buf[i] = self.buf[(self.head + 2 + i) % rt.MAILBOX_BUF_SIZE];
        }
        self.head = (self.head + 2 + msg_len) % rt.MAILBOX_BUF_SIZE;
        self.used -= (2 + msg_len);
        self.count -= 1;
        return out_buf[0..capped];
    }
};

pub const VerveProcess = struct {
    id: i64,
    alive: bool,
    process_type: i64,
    state_ptr: usize = 0, // Pointer to typed state struct (arena-allocated)
    mailbox: Mailbox,
    watcher_pids: [rt.MAX_WATCHERS]i64,
    watcher_count: usize,
    arena: rt.Arena,
};

/// Dispatch function receives raw message bytes: (msg_ptr, msg_len) -> result i64
pub const DispatchFn = *const fn ([*]const u8, usize) i64;

/// Dynamic process table — heap-allocated, grows by doubling.
pub var process_table: []VerveProcess = &.{};
pub var process_count: i64 = 0;
pub var current_process_id: i64 = 0;
pub var dispatch_table: []DispatchFn = &.{};

pub fn ensureProcessCapacity(min_count: usize) void {
    if (min_count <= process_table.len) return;
    const new_cap = @max(min_count, if (process_table.len == 0) rt.MAX_PROCESSES else process_table.len * 2);
    const new_table = std.heap.page_allocator.alloc(VerveProcess, new_cap) catch return;
    const new_dispatch = std.heap.page_allocator.alloc(DispatchFn, new_cap) catch return;
    // Copy existing
    if (process_table.len > 0) {
        @memcpy(new_table[0..process_table.len], process_table);
        @memcpy(new_dispatch[0..dispatch_table.len], dispatch_table);
    }
    // Init new slots
    for (process_table.len..new_cap) |i| {
        new_table[i] = .{
            .id = 0,
            .alive = false,
            .process_type = 0,
            .state_ptr = 0,
            .mailbox = .{},
            .watcher_pids = @splat(0),
            .watcher_count = 0,
            .arena = .{},
        };
        new_dispatch[i] = &dispatch_noop;
    }
    process_table = new_table;
    dispatch_table = new_dispatch;
}

fn dispatch_noop(_: [*]const u8, _: usize) i64 {
    return rt.makeTagged(1, 0);
}

pub fn pidx(pid: i64) usize {
    return @intCast(@as(u64, @bitCast(pid - 1)));
}

// ── Process operations ─────────────────────────────

pub fn verve_spawn(process_type: i64) i64 {
    ensureProcessCapacity(1); // ensure table exists
    // Find a slot: prefer recycling dead processes, then use new slot
    var idx: usize = process_table.len; // sentinel: not found
    for (process_table, 0..) |*p, i| {
        if (!p.alive and p.id != 0) {
            p.arena.freeAll();
            idx = i;
            break;
        }
    }
    if (idx == process_table.len) {
        // No dead slot — use next available
        const next: usize = @intCast(@as(u64, @bitCast(process_count)));
        ensureProcessCapacity(next + 1); // grow if needed
        idx = next;
        process_count += 1;
    }
    process_table[idx] = .{
        .id = @intCast(idx + 1),
        .alive = true,
        .process_type = process_type,
        .state_ptr = 0,
        .mailbox = .{},
        .watcher_pids = @splat(0),
        .watcher_count = 0,
        .arena = .{},
    };
    return process_count;
}

/// Get pointer to the current process's typed state struct.
pub fn verve_state_ptr() usize {
    const idx = pidx(current_process_id);
    return process_table[idx].state_ptr;
}

/// Set the state pointer for the current process (called at spawn time).
pub fn verve_state_init(ptr: usize) void {
    const idx = pidx(current_process_id);
    process_table[idx].state_ptr = ptr;
}

pub fn verve_watch(target_pid: i64) void {
    const idx = pidx(target_pid);
    const wc = process_table[idx].watcher_count;
    process_table[idx].watcher_pids[wc] = current_process_id;
    process_table[idx].watcher_count = wc + 1;
}

pub fn verve_kill(target_pid: i64) void {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    proc.alive = false;
    // Notify watchers before freeing arena — send a 2-byte death notification
    // Format: [handler_id=0xFF (sentinel for death)][param_count=0]
    for (0..proc.watcher_count) |i| {
        const watcher_pid = proc.watcher_pids[i];
        const widx = pidx(watcher_pid);
        const watcher = &process_table[widx];
        if (!watcher.alive) continue;
        const death_msg = [_]u8{ 0xFF, 0 };
        _ = watcher.mailbox.push(&death_msg, 2);
    }
    // Free all memory owned by this process
    proc.arena.freeAll();
}

/// Exit the current process — marks it dead and frees its arena.
/// Called by a handler to self-terminate (spawn-per-message pattern).
pub fn verve_exit_self() void {
    if (current_process_id <= 0) return;
    const idx = pidx(current_process_id);
    if (idx >= process_table.len) return;
    const proc = &process_table[idx];
    proc.alive = false;
    // Arena freed on next spawn that recycles this slot
}

// ── Message passing ────────────────────────────────

pub fn verve_drain(target_pid: i64) void {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    var pop_buf: [8192]u8 = undefined;
    while (proc.mailbox.pop(&pop_buf)) |msg| {
        if (!proc.alive) break;
        if (msg.len >= 1 and msg[0] == 0xFF) continue; // death notification sentinel
        const saved = current_process_id;
        current_process_id = target_pid;
        const pt: usize = @intCast(@as(u64, @bitCast(proc.process_type)));
        const result = dispatch_table[pt](msg.ptr, msg.len);
        current_process_id = saved;
        if (proc.mailbox.reply_slot) |slot| {
            slot.* = result;
            proc.mailbox.reply_slot = null;
        }
    }
}

/// Synchronous send: encode message, push to mailbox, drain, return result.
pub fn verve_send(target_pid: i64, msg_ptr: [*]const u8, msg_len: usize) i64 {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    if (!proc.alive) return rt.makeTagged(1, 0);
    var result: i64 = 0;
    proc.mailbox.reply_slot = &result;
    if (!proc.mailbox.push(msg_ptr, msg_len)) {
        proc.mailbox.reply_slot = null;
        return rt.makeTagged(1, 0);
    }
    verve_drain(target_pid);
    proc.mailbox.reply_slot = null;
    if (result > 0x10000 and rt.getTag(result) == 1) return result;
    return rt.makeTagged(0, result);
}

/// Fire-and-forget tell: encode message, push to mailbox, drain.
pub fn verve_tell(target_pid: i64, msg_ptr: [*]const u8, msg_len: usize) void {
    const idx = pidx(target_pid);
    if (idx >= process_table.len) return;
    const proc = &process_table[idx];
    if (!proc.alive) return;
    if (!proc.mailbox.push(msg_ptr, msg_len)) return;
    verve_drain(target_pid);
}

/// Send with timeout (timeout not enforced in single-threaded runtime).
pub fn verve_send_timeout(target_pid: i64, msg_ptr: [*]const u8, msg_len: usize, timeout_ms: i64) i64 {
    _ = timeout_ms;
    return verve_send(target_pid, msg_ptr, msg_len);
}
