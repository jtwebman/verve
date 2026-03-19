const std = @import("std");
const ast = @import("ast.zig");
const Value = @import("value.zig").Value;

pub const ProcessId = u64;

pub const Message = struct {
    handler_name: []const u8,
    args: []const Value,
    reply_to: ?ProcessId, // null for tell, set for send
    timeout_ms: ?i64, // null for tell
};

pub const MAILBOX_CAPACITY: usize = 10000;
pub const MAX_WATCHERS: usize = 100;

pub const Process = struct {
    id: ProcessId,
    name: []const u8,
    decl: ast.ProcessDecl,
    state: std.StringHashMapUnmanaged(Value),
    mailbox: std.ArrayListUnmanaged(Message),
    mailbox_capacity: usize,
    watchers: std.ArrayListUnmanaged(ProcessId),
    alive: bool,
    alloc: std.mem.Allocator,

    pub fn init(id: ProcessId, name: []const u8, decl: ast.ProcessDecl, alloc: std.mem.Allocator) Process {
        return .{
            .id = id,
            .name = name,
            .decl = decl,
            .state = .{},
            .mailbox = .{},
            .mailbox_capacity = MAILBOX_CAPACITY,
            .watchers = .{},
            .alive = true,
            .alloc = alloc,
        };
    }

    pub fn getState(self: *Process, key: []const u8) ?Value {
        return self.state.get(key);
    }

    pub fn setState(self: *Process, key: []const u8, value: Value) !void {
        try self.state.put(self.alloc, key, value);
    }

    pub fn pushMessage(self: *Process, msg: Message) !void {
        if (self.mailbox.items.len >= self.mailbox_capacity) {
            return error.OutOfMemory; // mailbox full
        }
        try self.mailbox.append(self.alloc, msg);
    }

    pub fn popMessage(self: *Process) ?Message {
        if (self.mailbox.items.len == 0) return null;
        // Remove from front (FIFO)
        const msg = self.mailbox.items[0];
        var i: usize = 0;
        while (i < self.mailbox.items.len - 1) : (i += 1) {
            self.mailbox.items[i] = self.mailbox.items[i + 1];
        }
        self.mailbox.items.len -= 1;
        return msg;
    }

    pub fn addWatcher(self: *Process, watcher_id: ProcessId) !void {
        try self.watchers.append(self.alloc, watcher_id);
    }

    pub fn findHandler(self: *Process, name: []const u8) ?ast.ReceiveDecl {
        for (self.decl.receive_handlers) |handler| {
            if (std.mem.eql(u8, handler.name, name)) return handler;
        }
        return null;
    }
};

pub const Scheduler = struct {
    processes: std.AutoHashMapUnmanaged(ProcessId, *Process),
    next_id: ProcessId,
    alloc: std.mem.Allocator,
    // responses from synchronous sends (single-threaded interpreter)
    pending_response: ?Value,

    pub fn init(alloc: std.mem.Allocator) Scheduler {
        return .{
            .processes = .{},
            .next_id = 1,
            .alloc = alloc,
            .pending_response = null,
        };
    }

    pub fn spawn(self: *Scheduler, name: []const u8, decl: ast.ProcessDecl) !ProcessId {
        const id = self.next_id;
        self.next_id += 1;

        const proc = try self.alloc.create(Process);
        proc.* = Process.init(id, name, decl, self.alloc);

        // Initialize state fields with default values
        for (decl.state_fields) |field| {
            const default_val: Value = switch (field.type_expr) {
                .simple => |type_name| blk: {
                    if (std.mem.eql(u8, type_name, "int")) break :blk .{ .int = 0 };
                    if (std.mem.eql(u8, type_name, "float")) break :blk .{ .float = 0.0 };
                    if (std.mem.eql(u8, type_name, "bool")) break :blk .{ .bool = false };
                    if (std.mem.eql(u8, type_name, "string")) break :blk .{ .string = "" };
                    break :blk .{ .none = {} };
                },
                else => .{ .none = {} },
            };
            try proc.setState(field.name, default_val);
        }

        try self.processes.put(self.alloc, id, proc);
        return id;
    }

    pub fn getProcess(self: *Scheduler, id: ProcessId) ?*Process {
        return self.processes.get(id);
    }

    pub fn getProcessByName(self: *Scheduler, name: []const u8) ?*Process {
        var iter = self.processes.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.*.name, name)) {
                return entry.value_ptr.*;
            }
        }
        return null;
    }

    pub fn killProcess(self: *Scheduler, id: ProcessId, reason: []const u8) !void {
        const proc = self.processes.get(id) orelse return;
        proc.alive = false;

        // Notify watchers
        for (proc.watchers.items) |watcher_id| {
            const watcher = self.processes.get(watcher_id) orelse continue;
            if (!watcher.alive) continue;
            try watcher.pushMessage(.{
                .handler_name = "ProcessDied",
                .args = &.{
                    .{ .int = @intCast(id) },
                    .{ .tag = reason },
                },
                .reply_to = null,
                .timeout_ms = null,
            });
        }
    }

    pub fn watch(self: *Scheduler, watcher_id: ProcessId, target_id: ProcessId) !void {
        const target = self.processes.get(target_id) orelse return;
        try target.addWatcher(watcher_id);
    }
};
