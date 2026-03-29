const std = @import("std");
const rt = @import("runtime.zig");
const fiber = @import("fiber.zig");

// ── Process runtime ────────────────────────────────

/// Byte ring buffer mailbox. Messages are variable-size binary-encoded byte sequences.
/// Format per message: [msg_len: u16][handler_id: u8][param_count: u8][params...]
/// The msg_len prefix allows popping without decoding the full message.
pub const Mailbox = struct {
    buf: [rt.MAILBOX_BUF_SIZE]u8 = undefined,
    head: usize = 0,
    used: usize = 0, // bytes used in buffer
    count: usize = 0, // number of messages
    reply_slot: ?*usize = null, // for synchronous send
    mutex: std.Thread.Mutex = .{}, // thread-safe push/pop

    /// Push a message (raw bytes) into the mailbox. Returns false if no room.
    pub fn push(self: *Mailbox, msg: [*]const u8, msg_len: usize) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
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
        self.mutex.lock();
        defer self.mutex.unlock();
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
    id: usize,
    alive: bool,
    process_type: usize,
    state_ptr: usize = 0, // Pointer to typed state struct (arena-allocated)
    max_messages: usize = 64, // configurable per-process mailbox limit
    mailbox: Mailbox,
    watcher_pids: [rt.MAX_WATCHERS]usize,
    watcher_count: usize,
    arena: rt.Arena,
    // Fiber support for cooperative scheduling
    proc_fiber: ?fiber.Fiber = null, // null = legacy sync mode
    yielded: bool = false, // true if process called yield and has more work
    io_wait_fd: std.posix.fd_t = -1, // fd this process is waiting on (-1 = none)
    owner_thread: usize = 0, // which scheduler thread owns this process
    reductions: u32 = 4000, // reduction counter for cooperative preemption
};

/// Dispatch function receives raw message bytes: (msg_ptr, msg_len) -> result usize
pub const DispatchFn = *const fn ([*]const u8, usize) usize;

/// Dynamic process table — heap-allocated, grows by doubling.
/// Protected by table_lock: write lock for spawn/kill/resize, read lock for access.
pub var process_table: []VerveProcess = &.{};
pub var process_count: usize = 0;
pub threadlocal var current_process_id: usize = 0;
pub var dispatch_table: []DispatchFn = &.{};
pub var table_lock: std.Thread.RwLock = .{};

// ── Scheduler state ───────────────────────────────

pub var scheduler_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub const SchedulerThread = struct {
    id: usize,
    scheduler_context: fiber.Context = .{},
    epoll_fd: i32 = -1,
    local_pids: std.ArrayListUnmanaged(usize) = .{},
    next_pid: ?usize = null, // LIFO slot: hot process to run next
    alloc: std.mem.Allocator,

    pub fn init(id: usize, alloc: std.mem.Allocator) SchedulerThread {
        return .{ .id = id, .alloc = alloc };
    }

    pub fn ensureEpoll(self: *SchedulerThread) void {
        if (self.epoll_fd >= 0) return;
        self.epoll_fd = std.posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC) catch -1;
    }

    pub fn addProcess(self: *SchedulerThread, pid: usize) void {
        self.local_pids.append(self.alloc, pid) catch {};
    }

    pub fn removeProcess(self: *SchedulerThread, pid: usize) void {
        for (self.local_pids.items, 0..) |p, i| {
            if (p == pid) {
                _ = self.local_pids.swapRemove(i);
                return;
            }
        }
    }
};

const MAX_THREADS = 64;
pub var scheduler_threads: [MAX_THREADS]?*SchedulerThread = .{null} ** MAX_THREADS;
pub var thread_count: usize = 0;
pub threadlocal var current_thread: ?*SchedulerThread = null;
var next_thread_idx: usize = 0; // round-robin assignment

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

fn dispatch_noop(_: [*]const u8, _: usize) usize {
    return rt.makeTagged(1, 0);
}

pub fn pidx(pid: usize) usize {
    return pid - 1;
}

// ── Process operations ─────────────────────────────

pub fn verve_spawn(process_type: usize) usize {
    const t = rt.profile.begin();
    defer rt.profile.end(.spawn, t);

    table_lock.lock();
    defer table_lock.unlock();

    ensureProcessCapacity(1); // ensure table exists
    // Find a slot: prefer recycling dead processes, then use new slot
    var idx: usize = process_table.len; // sentinel: not found
    for (process_table, 0..) |*p, i| {
        if (!p.alive and p.id != 0) {
            p.arena.freeAll();
            // Keep fiber stack for reuse (avoid expensive mmap/mprotect)
            idx = i;
            break;
        }
    }
    if (idx == process_table.len) {
        // No dead slot — use next available
        ensureProcessCapacity(process_count + 1); // grow if needed
        idx = process_count;
        process_count += 1;
    }
    const pid: usize = idx + 1;
    process_table[idx] = .{
        .id = pid,
        .alive = true,
        .process_type = process_type,
        .state_ptr = 0,
        .mailbox = .{},
        .watcher_pids = @splat(0),
        .watcher_count = 0,
        .arena = .{},
    };

    // Assign to scheduler thread (round-robin if multiple threads, else current)
    if (current_thread) |ct| {
        process_table[idx].owner_thread = ct.id;
        ct.addProcess(pid);
    } else if (thread_count > 0) {
        const tid = next_thread_idx % thread_count;
        next_thread_idx += 1;
        process_table[idx].owner_thread = tid;
        if (scheduler_threads[tid]) |st| {
            st.addProcess(pid);
        }
    }
    return pid;
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

pub fn verve_watch(target_pid: usize) void {
    const idx = pidx(target_pid);
    const wc = process_table[idx].watcher_count;
    if (wc >= rt.MAX_WATCHERS) return;
    process_table[idx].watcher_pids[wc] = current_process_id;
    process_table[idx].watcher_count = wc + 1;
}

pub fn verve_kill(target_pid: usize) void {
    table_lock.lock();
    defer table_lock.unlock();
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
    if (current_process_id == 0) return;
    const idx = pidx(current_process_id);
    if (idx >= process_table.len) return;
    const proc = &process_table[idx];
    proc.alive = false;
    proc.yielded = false;
    // Arena freed on next spawn that recycles this slot
}

// ── Message passing ────────────────────────────────

/// Drain ONE message from the mailbox. Returns true if a message was dispatched.
/// Caller must NOT hold table_lock — dispatch calls user code that may spawn.
fn drain_one(target_pid: usize) bool {
    // Read table under shared lock to get dispatch fn and pop message
    table_lock.lockShared();
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    var pop_buf: [8192]u8 = undefined;
    const msg = proc.mailbox.pop(&pop_buf) orelse {
        table_lock.unlockShared();
        return false;
    };
    if (!proc.alive) {
        table_lock.unlockShared();
        return false;
    }
    if (msg.len >= 1 and msg[0] == 0xFF) {
        table_lock.unlockShared();
        return true; // death notification — consumed but skip
    }
    const dispatch_fn = dispatch_table[proc.process_type];
    const reply_slot = proc.mailbox.reply_slot;
    table_lock.unlockShared();

    // Dispatch outside lock — user code may call spawn (needs write lock)
    const saved = current_process_id;
    current_process_id = target_pid;
    const result = dispatch_fn(msg.ptr, msg.len);
    current_process_id = saved;

    // Write reply under shared lock
    if (reply_slot) |slot| {
        table_lock.lockShared();
        process_table[idx].mailbox.reply_slot = null;
        table_lock.unlockShared();
        slot.* = result;
    }
    return true;
}

/// Drain ALL messages (legacy sync path).
pub fn verve_drain(target_pid: usize) void {
    const t = rt.profile.begin();
    defer rt.profile.end(.drain, t);

    while (drain_one(target_pid)) {
        if (!process_table[pidx(target_pid)].alive) break;
    }
}

/// Synchronous send: encode message, push to mailbox, drain, return result.
pub fn verve_send(target_pid: usize, msg_ptr: [*]const u8, msg_len: usize) usize {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    if (!proc.alive) return rt.makeTaggedStr(1, "process_dead");
    if (proc.mailbox.count >= proc.max_messages) return rt.makeTaggedStr(1, "mailbox_full");
    var result: usize = 0;
    proc.mailbox.reply_slot = &result;
    if (!proc.mailbox.push(msg_ptr, msg_len)) {
        proc.mailbox.reply_slot = null;
        return rt.makeTaggedStr(1, "mailbox_full");
    }
    // Always drain synchronously for send (caller needs the result)
    verve_drain(target_pid);
    proc.mailbox.reply_slot = null;
    if (result > 0x10000 and rt.getTag(result) == 1) return result;
    return rt.makeTagged(0, @intCast(result));
}

/// Fire-and-forget tell: push message to mailbox.
/// Returns tagged value: :ok{0} on success, :error{"mailbox_full"} or :error{"process_dead"} on failure.
/// When scheduler is running, message is deferred to scheduler.
/// When scheduler is not running, drains immediately (legacy behavior).
pub fn verve_tell(target_pid: usize, msg_ptr: [*]const u8, msg_len: usize) usize {
    const idx = pidx(target_pid);
    if (idx >= process_table.len) return rt.makeTaggedStr(1, "process_dead");
    const proc = &process_table[idx];
    if (!proc.alive) return rt.makeTaggedStr(1, "process_dead");
    if (proc.mailbox.count >= proc.max_messages) return rt.makeTaggedStr(1, "mailbox_full");
    if (!proc.mailbox.push(msg_ptr, msg_len)) return rt.makeTaggedStr(1, "mailbox_full");
    if (!scheduler_running.load(.acquire)) {
        verve_drain(target_pid);
    } else {
        // Set LIFO slot if target is on same thread (cache-hot optimization)
        if (current_thread) |ct| {
            if (proc.owner_thread == ct.id) {
                ct.next_pid = target_pid;
            }
        }
    }
    return rt.makeTagged(0, 0);
}

/// Set the maximum message count for a process mailbox.
pub fn verve_set_mailbox_size(target_pid: usize, max_messages: usize) void {
    const idx = pidx(target_pid);
    if (idx >= process_table.len) return;
    process_table[idx].max_messages = max_messages;
}

/// Send with timeout (timeout not enforced in single-threaded runtime).
pub fn verve_send_timeout(target_pid: usize, msg_ptr: [*]const u8, msg_len: usize, timeout_ms: i64) usize {
    _ = timeout_ms;
    return verve_send(target_pid, msg_ptr, msg_len);
}

// ── Cooperative scheduler ─────────────────────────

/// Returns true if any process on this thread (other than current) needs CPU time.
fn any_other_runnable_on_thread(thread: *SchedulerThread) bool {
    for (thread.local_pids.items) |pid| {
        const i = pidx(pid);
        if (i >= process_table.len) continue;
        const p = &process_table[i];
        if (!p.alive) continue;
        if (p.id == current_process_id) continue;
        if (p.yielded or p.mailbox.count > 0) return true;
    }
    return false;
}

/// Yield the current process. Pauses execution and returns to the scheduler.
/// If no other process needs CPU, this is a no-op (avoids wasted context switch).
pub fn verve_yield() i64 {
    if (!scheduler_running.load(.acquire)) return 0;
    const thread = current_thread orelse return 0;
    if (!any_other_runnable_on_thread(thread)) return 0;

    const idx = pidx(current_process_id);
    process_table[idx].yielded = true;
    fiber.context_switch(&process_table[idx].proc_fiber.?.context, &thread.scheduler_context);
    return 0;
}

/// Yield until a file descriptor is readable. Registers fd with epoll,
/// suspends the process, and resumes when data arrives.
pub fn verve_io_yield(fd: i64) void {
    if (!scheduler_running.load(.acquire)) return;
    const thread = current_thread orelse return;
    const idx = pidx(current_process_id);
    process_table[idx].io_wait_fd = @intCast(fd);
    process_table[idx].yielded = false;

    thread.ensureEpoll();
    if (thread.epoll_fd >= 0) {
        var ev = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ONESHOT,
            .data = .{ .u64 = @intCast(process_table[idx].id) },
        };
        std.posix.epoll_ctl(thread.epoll_fd, std.os.linux.EPOLL.CTL_ADD, @intCast(fd), &ev) catch {
            std.posix.epoll_ctl(thread.epoll_fd, std.os.linux.EPOLL.CTL_MOD, @intCast(fd), &ev) catch {};
        };
    }

    fiber.context_switch(&process_table[idx].proc_fiber.?.context, &thread.scheduler_context);
}

/// Return the current process's PID.
pub fn verve_self() usize {
    return current_process_id;
}

/// Decrement reduction counter. If zero, yield to scheduler and reset.
/// Called at loop back-edges for cooperative preemption.
pub fn verve_yield_check() void {
    if (!scheduler_running.load(.acquire)) return;
    if (current_process_id == 0) return;
    const idx = pidx(current_process_id);
    if (process_table[idx].reductions > 0) {
        process_table[idx].reductions -= 1;
        return;
    }
    // Reductions exhausted — yield
    process_table[idx].reductions = 4000;
    _ = verve_yield();
}

/// Return the current scheduler thread ID (for testing parallelism).
pub fn verve_thread_id() i64 {
    if (current_thread) |t| return @intCast(t.id);
    return 0;
}

/// Fiber entry point for each process. Drains one message at a time,
/// yielding back to the scheduler between messages.
fn process_fiber_entry(pid_raw: usize) void {
    const pid: usize = pid_raw;
    while (true) {
        const idx = pidx(pid);
        if (!process_table[idx].alive) break;

        const had_msg = drain_one(pid);

        if (!process_table[idx].alive) break;

        if (had_msg) {
            process_table[idx].yielded = (process_table[idx].mailbox.count > 0) or process_table[idx].yielded;
        }

        // Return to scheduler
        const thread = current_thread orelse break;
        fiber.context_switch(&process_table[idx].proc_fiber.?.context, &thread.scheduler_context);
    }
    const idx = pidx(pid_raw);
    if (process_table[idx].proc_fiber) |*f| f.state = .done;
    if (current_thread) |thread| {
        fiber.context_switch(&process_table[idx].proc_fiber.?.context, &thread.scheduler_context);
    }
}

/// Ensure a process has a fiber ready to run.
/// Reuses existing stack memory if available, only allocates on first use.
fn ensure_fiber(proc: *VerveProcess) void {
    if (proc.proc_fiber) |*f| {
        if (f.state == .done or f.state == .fresh) {
            // Reinitialize the fiber's stack frame (reuse the stack memory)
            fiber.fiber_reinit(f, &process_fiber_entry, proc.id);
        }
        return;
    }
    proc.proc_fiber = fiber.Fiber{};
    fiber.fiber_init(&proc.proc_fiber.?, &process_fiber_entry, proc.id) catch {
        proc.proc_fiber = null;
    };
}

/// Run the cooperative scheduler on a single SchedulerThread.
/// Iterates only this thread's local_pids.
pub fn scheduler_run(thread: *SchedulerThread) i64 {
    current_thread = thread;
    defer current_thread = null;

    while (true) {
        var any_ran = false;

        // LIFO slot: run hot process first (Tokio optimization)
        if (thread.next_pid) |npid| {
            thread.next_pid = null;
            const ni = pidx(npid);
            if (ni < process_table.len) {
                const proc = &process_table[ni];
                if (proc.alive and (proc.yielded or proc.mailbox.count > 0)) {
                    any_ran = true;
                    ensure_fiber(proc);
                    if (proc.proc_fiber != null) {
                        proc.proc_fiber.?.state = .running;
                        proc.reductions = 4000;
                        current_process_id = proc.id;
                        fiber.context_switch(&thread.scheduler_context, &proc.proc_fiber.?.context);
                        current_process_id = 0;
                    }
                }
            }
        }

        // Round-robin through local processes
        for (thread.local_pids.items) |pid| {
            const i = pidx(pid);
            if (i >= process_table.len) continue;
            const proc = &process_table[i];
            if (!proc.alive) continue;
            if (!proc.yielded and proc.mailbox.count == 0) continue;

            any_ran = true;
            ensure_fiber(proc);
            if (proc.proc_fiber == null) continue;

            proc.proc_fiber.?.state = .running;
            proc.reductions = 4000;
            current_process_id = proc.id;
            fiber.context_switch(&thread.scheduler_context, &proc.proc_fiber.?.context);
            current_process_id = 0;
        }

        // Clean up dead processes from local list
        var j: usize = 0;
        while (j < thread.local_pids.items.len) {
            const pid = thread.local_pids.items[j];
            const pi = pidx(pid);
            if (pi < process_table.len and !process_table[pi].alive) {
                _ = thread.local_pids.swapRemove(j);
            } else {
                j += 1;
            }
        }

        if (!any_ran) {
            var any_alive = false;
            var any_io_wait = false;
            for (thread.local_pids.items) |pid| {
                const pi = pidx(pid);
                if (pi >= process_table.len) continue;
                if (process_table[pi].alive) {
                    any_alive = true;
                    if (process_table[pi].io_wait_fd >= 0) any_io_wait = true;
                }
            }
            if (!any_alive) break;
            if (!any_io_wait) break;

            thread.ensureEpoll();
            if (thread.epoll_fd < 0) break;

            var events: [64]std.os.linux.epoll_event = undefined;
            const n = std.posix.epoll_wait(thread.epoll_fd, &events, -1);
            if (n == 0) continue;

            for (events[0..n]) |ev| {
                const pid: usize = @intCast(ev.data.u64);
                const pidx_val = pidx(pid);
                if (pidx_val < process_table.len and process_table[pidx_val].alive) {
                    process_table[pidx_val].yielded = true;
                    process_table[pidx_val].io_wait_fd = -1;
                }
            }
        }
    }

    return 0;
}

/// Run the cooperative scheduler until no processes are alive or runnable.
/// Creates a single SchedulerThread (backward-compatible single-threaded mode).
pub fn verve_scheduler_run() i64 {
    return verve_scheduler_run_threaded(1);
}

/// Run the scheduler with N threads. N=0 means auto-detect CPU count.
pub fn verve_scheduler_run_threaded(num_threads_arg: usize) i64 {
    const alloc = std.heap.page_allocator;
    const num_threads = if (num_threads_arg == 0) (std.Thread.getCpuCount() catch 1) else num_threads_arg;

    scheduler_running.store(true, .release);
    defer scheduler_running.store(false, .release);

    // Create scheduler threads
    var threads_storage: [MAX_THREADS]SchedulerThread = undefined;
    var os_threads: [MAX_THREADS]?std.Thread = .{null} ** MAX_THREADS;
    thread_count = num_threads;

    for (0..num_threads) |i| {
        threads_storage[i] = SchedulerThread.init(i, alloc);
        scheduler_threads[i] = &threads_storage[i];
    }

    // Assign existing processes to threads (round-robin)
    for (0..process_count) |i| {
        if (i >= process_table.len) break;
        if (!process_table[i].alive) continue;
        const tid = i % num_threads;
        process_table[i].owner_thread = tid;
        scheduler_threads[tid].?.addProcess(process_table[i].id);
    }

    // Spawn N-1 worker threads
    for (1..num_threads) |i| {
        os_threads[i] = std.Thread.spawn(.{}, scheduler_thread_entry, .{scheduler_threads[i].?}) catch null;
    }

    // Run thread 0 on main thread
    _ = scheduler_run(scheduler_threads[0].?);

    // Join worker threads
    for (1..num_threads) |i| {
        if (os_threads[i]) |t| t.join();
    }

    // Clean up
    for (0..num_threads) |i| {
        scheduler_threads[i] = null;
    }
    thread_count = 0;

    return 0;
}

fn scheduler_thread_entry(thread: *SchedulerThread) void {
    _ = scheduler_run(thread);
}

/// Register current process as waiting for I/O on a file descriptor.
/// Process will be woken by the scheduler when the fd is readable.
pub fn verve_io_wait(fd: i64) void {
    if (current_process_id == 0) return;
    const idx = pidx(current_process_id);
    process_table[idx].io_wait_fd = @intCast(fd);
}
