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
    list: []Value,
    map: Map,
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

    pub const Map = struct {
        keys: []Value,
        values: []Value,
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
                for (v, 0..) |item, i| {
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
            .map => try writer.writeAll("map{...}"),
            .function_ref => |v| try writer.print("{s}.{s}", .{ v.module_name, v.fn_name }),
            .process_id => |v| try writer.print("process<{d}>", .{v}),
        }
    }
};
