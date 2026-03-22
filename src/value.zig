const std = @import("std");

pub const Value = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
    tag: []const u8, // :ok, :error, :USD
    tag_with_value: TagWithValue, // :ok{42}, :error{"reason"}
    none: void,
    void: void,
    list: *MutableList,
    map: *MutableMap,
    set: *MutableSet,
    stack: *MutableStack,
    queue: *MutableQueue,
    stream: *Stream,
    struct_val: StructVal,
    function_ref: FunctionRef,
    process_id: u64,

    // Poison values
    overflow: void,
    div_zero: void,
    out_of_bounds: void,
    nan: void,
    infinity: void,

    pub const TagWithValue = struct {
        tag: []const u8,
        values: []Value,
    };

    pub const MutableList = struct {
        items: std.ArrayListUnmanaged(Value),
        alloc: std.mem.Allocator,
        frozen: bool,

        pub fn init(alloc: std.mem.Allocator) MutableList {
            return .{ .items = .{}, .alloc = alloc, .frozen = false };
        }

        pub fn append(self: *MutableList, val: Value) !void {
            if (self.frozen) return error.FrozenCollection;
            try self.items.append(self.alloc, val);
        }

        pub fn len(self: *const MutableList) usize {
            return self.items.items.len;
        }

        pub fn get(self: *const MutableList, index: usize) ?Value {
            if (index >= self.items.items.len) return null;
            return self.items.items[index];
        }
    };

    pub const MutableMap = struct {
        keys: std.ArrayListUnmanaged(Value),
        values: std.ArrayListUnmanaged(Value),
        alloc: std.mem.Allocator,
        frozen: bool,

        pub fn init(alloc: std.mem.Allocator) MutableMap {
            return .{ .keys = .{}, .values = .{}, .alloc = alloc, .frozen = false };
        }

        pub fn put(self: *MutableMap, key: Value, val: Value) !void {
            if (self.frozen) return error.FrozenCollection;
            // Check for existing key
            for (self.keys.items, 0..) |k, i| {
                if (Value.eql(k, key)) {
                    self.values.items[i] = val;
                    return;
                }
            }
            try self.keys.append(self.alloc, key);
            try self.values.append(self.alloc, val);
        }

        pub fn getVal(self: *const MutableMap, key: Value) ?Value {
            for (self.keys.items, 0..) |k, i| {
                if (Value.eql(k, key)) return self.values.items[i];
            }
            return null;
        }

        pub fn len(self: *const MutableMap) usize {
            return self.keys.items.len;
        }
    };

    pub const MutableStack = struct {
        items: std.ArrayListUnmanaged(Value),
        alloc: std.mem.Allocator,
        frozen: bool,

        pub fn init(alloc: std.mem.Allocator) MutableStack {
            return .{ .items = .{}, .alloc = alloc, .frozen = false };
        }

        pub fn push(self: *MutableStack, val: Value) !void {
            if (self.frozen) return error.FrozenCollection;
            try self.items.append(self.alloc, val);
        }

        pub fn pop(self: *MutableStack) ?Value {
            if (self.frozen) return null;
            if (self.items.items.len == 0) return null;
            return self.items.pop();
        }

        pub fn peek(self: *const MutableStack) ?Value {
            if (self.items.items.len == 0) return null;
            return self.items.items[self.items.items.len - 1];
        }

        pub fn len(self: *const MutableStack) usize {
            return self.items.items.len;
        }
    };

    pub const MutableQueue = struct {
        items: std.ArrayListUnmanaged(Value),
        alloc: std.mem.Allocator,
        frozen: bool,

        pub fn init(alloc: std.mem.Allocator) MutableQueue {
            return .{ .items = .{}, .alloc = alloc, .frozen = false };
        }

        pub fn push(self: *MutableQueue, val: Value) !void {
            if (self.frozen) return error.FrozenCollection;
            try self.items.append(self.alloc, val);
        }

        pub fn pop(self: *MutableQueue) ?Value {
            if (self.frozen) return null;
            if (self.items.items.len == 0) return null;
            const val = self.items.items[0];
            _ = self.items.orderedRemove(0);
            return val;
        }

        pub fn peek(self: *const MutableQueue) ?Value {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        pub fn len(self: *const MutableQueue) usize {
            return self.items.items.len;
        }
    };

    pub const MutableSet = struct {
        items: std.ArrayListUnmanaged(Value),
        alloc: std.mem.Allocator,
        frozen: bool,

        pub fn init(alloc: std.mem.Allocator) MutableSet {
            return .{ .items = .{}, .alloc = alloc, .frozen = false };
        }

        pub fn add(self: *MutableSet, val: Value) !void {
            if (self.frozen) return error.FrozenCollection;
            // Check for duplicates
            for (self.items.items) |existing| {
                if (Value.eql(existing, val)) return;
            }
            try self.items.append(self.alloc, val);
        }

        pub fn has(self: *const MutableSet, val: Value) bool {
            for (self.items.items) |existing| {
                if (Value.eql(existing, val)) return true;
            }
            return false;
        }

        pub fn remove(self: *MutableSet, val: Value) void {
            if (self.frozen) return; // frozen collection
            for (self.items.items, 0..) |existing, i| {
                if (Value.eql(existing, val)) {
                    _ = self.items.orderedRemove(i);
                    return;
                }
            }
        }

        pub fn len(self: *const MutableSet) usize {
            return self.items.items.len;
        }
    };

    pub const Stream = struct {
        kind: Kind,
        closed: bool,

        pub const Kind = union(enum) {
            stdout: void,
            stderr: void,
            stdin: void,
            file_read: struct {
                content: []const u8,
                pos: usize,
            },
            file_write: struct {
                path: []const u8,
                buf: std.ArrayListUnmanaged(u8),
                alloc: std.mem.Allocator,
            },
        };

        pub fn initStdout() Stream {
            return .{ .kind = .{ .stdout = {} }, .closed = false };
        }

        pub fn initStderr() Stream {
            return .{ .kind = .{ .stderr = {} }, .closed = false };
        }

        pub fn initStdin() Stream {
            return .{ .kind = .{ .stdin = {} }, .closed = false };
        }

        pub fn initFileRead(content: []const u8) Stream {
            return .{ .kind = .{ .file_read = .{ .content = content, .pos = 0 } }, .closed = false };
        }

        pub fn initFileWrite(path: []const u8, alloc: std.mem.Allocator) Stream {
            return .{ .kind = .{ .file_write = .{ .path = path, .buf = .{}, .alloc = alloc } }, .closed = false };
        }
    };

    pub const StructVal = struct {
        name: []const u8,
        field_names: []const []const u8,
        field_values: []Value,
    };

    pub const FunctionRef = struct {
        module_name: []const u8,
        fn_name: []const u8,
    };

    pub fn isPoison(self: Value) bool {
        return switch (self) {
            .overflow, .div_zero, .out_of_bounds, .nan, .infinity => true,
            else => false,
        };
    }

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .bool => |b| b,
            .none => false,
            else => true,
        };
    }

    pub fn eql(a: Value, b: Value) bool {
        const Tag = std.meta.Tag(Value);
        const a_tag: Tag = a;
        const b_tag: Tag = b;
        if (a_tag != b_tag) return false;

        return switch (a) {
            .int => |av| av == b.int,
            .float => |av| av == b.float,
            .bool => |av| av == b.bool,
            .string => |av| std.mem.eql(u8, av, b.string),
            .tag => |av| std.mem.eql(u8, av, b.tag),
            .none => true,
            .void => true,
            .overflow => true,
            .div_zero => true,
            .out_of_bounds => true,
            .nan => true,
            .infinity => true,
            else => false,
        };
    }

    pub fn format(self: Value, writer: anytype) !void {
        switch (self) {
            .int => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
            .bool => |v| try writer.print("{}", .{v}),
            .string => |v| try writer.print("\"{s}\"", .{v}),
            .tag => |v| try writer.print(":{s}", .{v}),
            .tag_with_value => |v| {
                try writer.print(":{s}{{", .{v.tag});
                for (v.values, 0..) |val, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try val.format(writer);
                }
                try writer.writeAll("}");
            },
            .none => try writer.writeAll("none"),
            .void => try writer.writeAll("void"),
            .overflow => try writer.writeAll(":overflow"),
            .div_zero => try writer.writeAll(":div_zero"),
            .out_of_bounds => try writer.writeAll(":out_of_bounds"),
            .nan => try writer.writeAll(":nan"),
            .infinity => try writer.writeAll(":infinity"),
            .list => |v| {
                try writer.writeAll("[");
                for (v.items.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(writer);
                }
                try writer.writeAll("]");
            },
            .struct_val => |v| {
                try writer.print("{s}{{", .{v.name});
                for (v.field_names, 0..) |fname, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{s}: ", .{fname});
                    try v.field_values[i].format(writer);
                }
                try writer.writeAll("}");
            },
            .map => |v| {
                try writer.writeAll("map{");
                for (v.keys.items, 0..) |key, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try key.format(writer);
                    try writer.writeAll(": ");
                    try v.values.items[i].format(writer);
                }
                try writer.writeAll("}");
            },
            .set => |v| {
                try writer.writeAll("set{");
                for (v.items.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(writer);
                }
                try writer.writeAll("}");
            },
            .stack => |v| {
                try writer.writeAll("stack[");
                for (v.items.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(writer);
                }
                try writer.writeAll("]");
            },
            .queue => |v| {
                try writer.writeAll("queue[");
                for (v.items.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(writer);
                }
                try writer.writeAll("]");
            },
            .stream => |v| {
                const kind_name = switch (v.kind) {
                    .stdout => "stdout",
                    .stderr => "stderr",
                    .stdin => "stdin",
                    .file_read => "file(r)",
                    .file_write => "file(w)",
                };
                try writer.print("stream<{s}>", .{kind_name});
            },
            .function_ref => |v| try writer.print("{s}.{s}", .{ v.module_name, v.fn_name }),
            .process_id => |v| try writer.print("process<{d}>", .{v}),
        }
    }
};
