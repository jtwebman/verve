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
    state_ptr: usize = 0,
    max_messages: usize = 64,
    mailbox_ptr: ?*Mailbox = null, // heap-allocated on first push (saves 4KB per idle process)
    watcher_ptr: ?*WatcherList = null, // heap-allocated on first watch
    arena_ptr: ?*rt.Arena = null, // heap-allocated on first alloc
    proc_fiber: ?fiber.Fiber = null,
    yielded: bool = false,
    io_wait_fd: std.posix.fd_t = -1,
    owner_thread: usize = 0,
    reductions: u32 = 4000,
    send_result: usize = 0, // result from send handler
    send_result_ready: bool = false, // wake flag for send
    send_slot_owner: usize = 0, // PID of target allowed to write send_result
    parent_pid: usize = 0, // PID of spawning process (0 = top-level)

    /// Get or create mailbox (lazy allocation).
    pub fn mailbox(self: *VerveProcess) *Mailbox {
        if (self.mailbox_ptr) |m| return m;
        const m = std.heap.page_allocator.create(Mailbox) catch @panic("OOM: mailbox");
        m.* = .{};
        self.mailbox_ptr = m;
        return m;
    }

    /// Get or create arena (lazy allocation).
    pub fn arena(self: *VerveProcess) *rt.Arena {
        if (self.arena_ptr) |a| return a;
        const a = std.heap.page_allocator.create(rt.Arena) catch @panic("OOM: arena");
        a.* = .{};
        self.arena_ptr = a;
        return a;
    }

    /// Free all owned resources.
    pub fn freeResources(self: *VerveProcess) void {
        if (self.arena_ptr) |a| {
            a.freeAll();
            // Keep the arena struct for reuse
        }
        if (self.mailbox_ptr) |m| {
            m.head = 0;
            m.used = 0;
            m.count = 0;
        }
        if (self.watcher_ptr) |w| {
            w.count = 0;
        }
        self.send_result = 0;
        self.send_result_ready = false;
        self.send_slot_owner = 0;
        self.parent_pid = 0;
    }
};

pub const WatcherList = struct {
    pids: [rt.MAX_WATCHERS]usize = @splat(0),
    count: usize = 0,
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
var free_slots: std.ArrayListUnmanaged(usize) = .{}; // indices of dead process slots for O(1) reuse

/// PID layout: [ node_id: 12 bits | process_id: 36 bits ] = 48 bits in i64
/// node_id 0 = local, 1-4095 = remote. process_id is monotonic, never reused.
var next_pid_counter: u64 = 1; // monotonic counter, starts at 1 (0 = invalid)
var pid_to_idx: std.AutoHashMapUnmanaged(usize, usize) = .{}; // packed PID → table index

pub fn packPid(node_id: u12, process_id: u64) usize {
    return (@as(usize, node_id) << 36) | @as(usize, @truncate(process_id & 0xFFFFFFFFF));
}

pub fn unpackProcessId(pid: usize) u64 {
    return pid & 0xFFFFFFFFF;
}

pub fn unpackNodeId(pid: usize) u12 {
    return @truncate(pid >> 36);
}

// ── Scheduler state ───────────────────────────────

pub var scheduler_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
pub var program_exit_code: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);
pub var main_fn_ptr: ?*const fn (usize) usize = null;

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
    return pid_to_idx.get(pid) orelse return 0;
}

/// Returns true if the pid is a known, valid process (may be alive or dead).
pub fn pidValid(pid: usize) bool {
    return pid_to_idx.contains(pid);
}

// ── Process operations ─────────────────────────────

pub fn verve_spawn(process_type: usize) usize {
    const t = rt.profile.begin();
    defer rt.profile.end(.spawn, t);

    table_lock.lock();
    defer table_lock.unlock();

    ensureProcessCapacity(1); // ensure table exists
    // O(1) slot reuse via free list, fallback to next available
    var idx: usize = undefined;
    if (free_slots.items.len > 0) {
        idx = free_slots.items[free_slots.items.len - 1];
        free_slots.items.len -= 1;
        process_table[idx].freeResources();
    } else {
        ensureProcessCapacity(process_count + 1);
        idx = process_count;
        process_count += 1;
    }
    // Monotonic PID: pack as (node_id=0 << 36) | next_pid_counter
    const pid = packPid(0, next_pid_counter);
    next_pid_counter += 1;
    pid_to_idx.put(std.heap.page_allocator, pid, idx) catch {};

    // Reset process fields without reinitializing the 64KB mailbox buffer
    const proc = &process_table[idx];
    proc.id = pid;
    proc.alive = true;
    proc.process_type = process_type;
    proc.state_ptr = 0;
    if (proc.mailbox_ptr) |m| {
        m.head = 0;
        m.used = 0;
        m.count = 0;
    }
    if (proc.watcher_ptr) |w| w.count = 0;
    proc.yielded = false;
    proc.io_wait_fd = -1;
    proc.reductions = 4000;
    proc.send_result = 0;
    proc.send_result_ready = false;
    proc.send_slot_owner = 0;
    proc.parent_pid = current_process_id;

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
    const proc = &process_table[idx];
    // Lazy alloc watcher list
    if (proc.watcher_ptr == null) {
        proc.watcher_ptr = std.heap.page_allocator.create(WatcherList) catch return;
        proc.watcher_ptr.?.* = .{};
    }
    const w = proc.watcher_ptr.?;
    if (w.count >= rt.MAX_WATCHERS) return;
    w.pids[w.count] = current_process_id;
    w.count += 1;
}

/// Kill a process and all its children. Caller must hold table_lock.
fn kill_tree(pid: usize) void {
    if (!pidValid(pid)) return;
    const idx = pidx(pid);
    const proc = &process_table[idx];
    if (!proc.alive) return;
    proc.alive = false;
    proc.yielded = false;
    // Notify watchers
    const wc = if (proc.watcher_ptr) |w| w.count else 0;
    for (0..wc) |i| {
        const watcher_pid = proc.watcher_ptr.?.pids[i];
        const widx = pidx(watcher_pid);
        const watcher = &process_table[widx];
        if (!watcher.alive) continue;
        const death_msg = [_]u8{ 0xFF, 0 };
        _ = watcher.mailbox().push(&death_msg, 2);
    }
    // Wake any process waiting on a send to this process
    // Kill all children (parent owns children)
    for (process_table[0..process_count]) |*p| {
        if (p.alive and p.send_slot_owner == pid) {
            p.yielded = true;
        }
        if (p.alive and p.parent_pid == pid) {
            kill_tree(p.id);
        }
    }
    free_slots.append(std.heap.page_allocator, idx) catch {};
    _ = pid_to_idx.remove(pid);
}

pub fn verve_kill(target_pid: usize) void {
    table_lock.lock();
    defer table_lock.unlock();
    kill_tree(target_pid);
}

/// Exit the current process and all its children.
/// Called by a handler to self-terminate (spawn-per-message pattern).
pub fn verve_exit_self() void {
    if (current_process_id == 0) return;
    table_lock.lock();
    defer table_lock.unlock();
    kill_tree(current_process_id);
}

// ── Message passing ────────────────────────────────

/// Drain ONE message from the mailbox. Returns true if a message was dispatched.
/// Caller must NOT hold table_lock — dispatch calls user code that may spawn.
fn drain_one(target_pid: usize) bool {
    table_lock.lockShared();
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    var pop_buf: [8192]u8 = undefined;
    const msg = proc.mailbox().pop(&pop_buf) orelse {
        table_lock.unlockShared();
        return false;
    };
    if (!proc.alive) {
        table_lock.unlockShared();
        return false;
    }
    if (msg.len >= 1 and msg[0] == 0xFF) {
        table_lock.unlockShared();
        return true;
    }
    const dispatch_fn = dispatch_table[proc.process_type];
    table_lock.unlockShared();

    const saved = current_process_id;
    current_process_id = target_pid;
    // Dispatch handles reply writing for send handlers via generated code
    _ = dispatch_fn(msg.ptr, msg.len);
    current_process_id = saved;
    return true;
}

/// Synchronous send: push message to mailbox, yield until target processes it.
/// The generated send dispatch function writes the result to our send_result field.
pub fn verve_send(target_pid: usize, msg_ptr: [*]const u8, msg_len: usize) usize {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    if (!proc.alive) return rt.makeTaggedStr(1, "process_dead");
    if (proc.mailbox().count >= proc.max_messages) return rt.makeTaggedStr(1, "mailbox_full");
    if (!proc.mailbox().push(msg_ptr, msg_len)) return rt.makeTaggedStr(1, "mailbox_full");
    // Set up sender's reply slot
    const self_idx = pidx(current_process_id);
    const self_proc = &process_table[self_idx];
    self_proc.send_result = 0;
    self_proc.send_result_ready = false;
    self_proc.send_slot_owner = target_pid;
    // Hint scheduler to run the target next
    if (current_thread) |ct| {
        if (proc.owner_thread == ct.id) {
            ct.next_pid = target_pid;
        }
    }
    // Yield until dispatch writes our result or target dies
    while (!@as(*volatile bool, &self_proc.send_result_ready).* and isAlive(idx)) {
        self_proc.yielded = true;
        if (current_thread) |thread| {
            fiber.context_switch(&self_proc.proc_fiber.?.context, &thread.scheduler_context);
        } else break;
    }
    self_proc.send_slot_owner = 0;
    if (!self_proc.send_result_ready) return rt.makeTaggedStr(1, "process_dead");
    const result = self_proc.send_result;
    if (result > 0x10000 and rt.getTag(result) == 1) return result;
    return rt.makeTagged(0, @intCast(result));
}

/// Fire-and-forget tell: push message to mailbox.
/// Returns tagged value: :ok{0} on success, :error{"mailbox_full"} or :error{"process_dead"} on failure.
pub fn verve_tell(target_pid: usize, msg_ptr: [*]const u8, msg_len: usize) usize {
    if (!pidValid(target_pid)) return rt.makeTaggedStr(1, "process_dead");
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    if (!proc.alive) return rt.makeTaggedStr(1, "process_dead");
    if (proc.mailbox().count >= proc.max_messages) return rt.makeTaggedStr(1, "mailbox_full");
    if (!proc.mailbox().push(msg_ptr, msg_len)) return rt.makeTaggedStr(1, "mailbox_full");
    // Hint scheduler to run the target next (LIFO cache-hot optimization)
    if (current_thread) |ct| {
        if (proc.owner_thread == ct.id) {
            ct.next_pid = target_pid;
        }
    }
    return rt.makeTagged(0, 0);
}

/// Set the maximum message count for a process mailbox.
pub fn verve_set_mailbox_size(target_pid: usize, max_messages: usize) void {
    if (!pidValid(target_pid)) return;
    const idx = pidx(target_pid);
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
        if (!pidValid(pid)) continue;
        const i = pidx(pid);
        const p = &process_table[i];
        if (!p.alive) continue;
        if (p.id == current_process_id) continue;
        if (p.yielded or (if (p.mailbox_ptr) |m| m.count > 0 else false)) return true;
    }
    return false;
}

/// Yield the current process. Pauses execution and returns to the scheduler.
/// If no other process needs CPU, this is a no-op (avoids wasted context switch).
pub fn verve_yield() i64 {
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
fn isAlive(idx: usize) bool {
    return @as(*volatile bool, &process_table[idx].alive).*;
}

fn process_fiber_entry(pid_raw: usize) void {
    const pid: usize = pid_raw;
    while (true) {
        const idx = pidx(pid);
        if (!isAlive(idx)) break;

        const had_msg = drain_one(pid);

        if (!isAlive(idx)) break;

        if (had_msg) {
            // Set yielded if more messages remain; clear it otherwise so the
            // scheduler doesn't spin on an idle process.
            process_table[idx].yielded = if (process_table[idx].mailbox_ptr) |m| m.count > 0 else false;
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

/// Fiber entry for the synthetic main process. Calls the user's main function,
/// stores its exit code, then marks itself dead and returns to the scheduler.
fn main_process_fiber_entry(pid_raw: usize) void {
    const pid: usize = pid_raw;
    const result = if (main_fn_ptr) |f| f(0) else 0;
    program_exit_code.store(@intCast(result), .release);
    // Kill main and all its children
    verve_kill(pid);
    const idx = pidx(pid);
    if (process_table[idx].proc_fiber) |*f| f.state = .done;
    if (current_thread) |thread| {
        fiber.context_switch(&process_table[idx].proc_fiber.?.context, &thread.scheduler_context);
    }
}

/// Spawn a synthetic process for module main. Uses main_process_fiber_entry
/// instead of the normal message-draining fiber entry. Uses a larger stack
/// (256KB) since user main functions have full local variable arrays.
pub fn verve_spawn_main(main_fn: *const fn (usize) usize) usize {
    main_fn_ptr = main_fn;
    const pid = verve_spawn(0xFFFF);
    const idx = pidx(pid);
    var proc = &process_table[idx];
    proc.yielded = true; // make it schedulable immediately
    // Create fiber with main_process_fiber_entry and large stack
    proc.proc_fiber = fiber.Fiber{};
    fiber.fiber_init_sized(&proc.proc_fiber.?, &main_process_fiber_entry, pid, 256 * 1024) catch {
        proc.proc_fiber = null;
    };
    if (proc.proc_fiber) |*f| f.state = .running;
    return pid;
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
            if (pidValid(npid)) {
                const ni = pidx(npid);
                const proc = &process_table[ni];
                if (proc.alive and (proc.yielded or (if (proc.mailbox_ptr) |m| m.count > 0 else false))) {
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
            if (!pidValid(pid)) continue;
            const i = pidx(pid);
            const proc = &process_table[i];
            if (!proc.alive) continue;
            if (!proc.yielded and (if (proc.mailbox_ptr) |m| m.count == 0 else true)) continue;

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
            if (!pidValid(pid) or !process_table[pidx(pid)].alive) {
                _ = thread.local_pids.swapRemove(j);
            } else {
                j += 1;
            }
        }

        if (!any_ran) {
            var any_alive = false;
            var any_io_wait = false;
            for (thread.local_pids.items) |pid| {
                if (!pidValid(pid)) continue;
                const pi = pidx(pid);
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
                if (pidValid(pid)) {
                    const pidx_val = pidx(pid);
                    if (process_table[pidx_val].alive) {
                        process_table[pidx_val].yielded = true;
                        process_table[pidx_val].io_wait_fd = -1;
                    }
                }
            }
        }
    }

    return 0;
}

/// Run the scheduler with auto-detected CPU count.
pub fn verve_scheduler_run() i64 {
    return verve_scheduler_run_threaded(0); // 0 = auto-detect
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
