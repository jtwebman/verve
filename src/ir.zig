const std = @import("std");

/// Verve IR — typed, target-independent intermediate representation.
/// SSA-style: each instruction produces a value in a virtual register.
/// Types are monomorphized: int is bare i64, not a tagged union.
/// No OS-specific operations — backends map builtins to syscalls/APIs.
pub const Type = enum {
    i64,
    f64,
    bool,
    string,
    void,
};

/// Virtual register. Instructions produce and consume these.
pub const Reg = u32;
pub const BlockId = u32;

pub const Inst = union(enum) {
    // ── Constants ────────────────────────────────────────
    const_int: struct { dest: Reg, value: i64 },
    const_float: struct { dest: Reg, value: f64 },
    const_bool: struct { dest: Reg, value: bool },
    const_string: struct { dest: Reg, value: []const u8 },

    // ── Arithmetic (i64) ────────────────────────────────
    add_i64: BinOp,
    sub_i64: BinOp,
    mul_i64: BinOp,
    div_i64: BinOp,
    mod_i64: BinOp,
    neg_i64: UnOp,

    // ── Float arithmetic (values stored as bitcast i64) ─
    add_f64: BinOp,
    sub_f64: BinOp,
    mul_f64: BinOp,
    div_f64: BinOp,
    mod_f64: BinOp,
    neg_f64: UnOp,

    // ── Comparison ──────────────────────────────────────
    eq_i64: BinOp,
    neq_i64: BinOp,
    lt_i64: BinOp,
    gt_i64: BinOp,
    lte_i64: BinOp,
    gte_i64: BinOp,

    // ── Float comparison (returns bool as i64) ──────────
    eq_f64: BinOp,
    neq_f64: BinOp,
    lt_f64: BinOp,
    gt_f64: BinOp,
    lte_f64: BinOp,
    gte_f64: BinOp,

    // ── Logical ─────────────────────────────────────────
    and_bool: BinOp,
    or_bool: BinOp,
    not_bool: UnOp,

    // ── Variables ───────────────────────────────────────
    load_local: struct { dest: Reg, name: []const u8 },
    store_local: struct { name: []const u8, src: Reg },

    // ── Control flow ────────────────────────────────────
    jump: struct { target: BlockId },
    branch: struct { cond: Reg, then_block: BlockId, else_block: BlockId },
    ret: struct { value: ?Reg },
    break_loop: void,
    continue_loop: void,

    /// Reduction check: decrement process reductions counter, yield if zero.
    /// Inserted at loop back-edges for cooperative preemption.
    yield_check: void,

    // ── Tagged values ────────────────────────────────────
    tag_get: struct { dest: Reg, tagged: Reg },
    tag_value: struct { dest: Reg, tagged: Reg },
    tag_value_str: struct { dest: Reg, tagged: Reg }, // extract string from tagged value

    // ── Calls ───────────────────────────────────────────
    /// Call a user-defined function.
    call: struct { dest: Reg, module: []const u8, function: []const u8, args: []const Reg },
    // ── Structs ──────────────────────────────────────────
    /// Allocate a typed struct instance, store pointer in dest.
    struct_alloc: struct { dest: Reg, struct_name: []const u8 },
    /// Store value into typed struct field.
    struct_store: struct { base: Reg, struct_name: []const u8, field_name: []const u8, src: Reg },
    /// Load value from typed struct field.
    struct_load: struct { dest: Reg, base: Reg, struct_name: []const u8, field_name: []const u8 },

    // ── Lists ───────────────────────────────────────────
    /// Allocate a new list (returns pointer to list header)
    list_new: struct { dest: Reg },
    /// Append a value to a list
    list_append: struct { list: Reg, value: Reg },
    /// Get list length
    list_len: struct { dest: Reg, list: Reg },
    /// Get list element by index
    list_get: struct { dest: Reg, list: Reg, index: Reg },

    // ── String operations ────────────────────────────────
    /// Get byte at index as integer: dest = string[index] as i64
    string_byte_at: struct { dest: Reg, str: Reg, index: Reg },
    /// Get pointer to byte at index (single-char string): dest = &string[index]
    string_index: struct { dest: Reg, str: Reg, index: Reg },
    /// Slice a string: dest = str[start..end] ([]const u8)
    string_slice: struct { dest: Reg, str: Reg, start: Reg, end: Reg },
    /// Get string byte length: dest = str.len (i64 from []const u8)
    string_len: struct { dest: Reg, str: Reg },
    /// Compare two strings for equality: dest = (a == b), both are []const u8
    string_eq: struct { dest: Reg, lhs: Reg, rhs: Reg },

    /// Call a platform builtin. The backend maps these to OS-specific operations.
    /// Examples: "exit", "write_stdout", "write_stderr"
    call_builtin: struct { dest: Reg, name: []const u8, args: []const Reg },

    // ── Process operations ──────────────────────────────────
    /// Spawn a new process instance, returns PID in dest.
    process_spawn: struct { dest: Reg, process_type: u32 },
    /// Send a message to a process (synchronous call), result in dest.
    process_send: struct { dest: Reg, target: Reg, handler_index: u32, args: []const Reg },
    /// Tell a process (fire-and-forget). Returns Result<void> tagged value.
    process_tell: struct { dest: Reg, target: Reg, handler_index: u32, args: []const Reg },
    /// Read process state field into dest.
    process_state_get: struct { dest: Reg, struct_name: []const u8, field_name: []const u8 },
    /// Write value to process state field.
    process_state_set: struct { struct_name: []const u8, field_name: []const u8, src: Reg },
    /// Register current process as watcher of target.
    process_watch: struct { target: Reg },
    /// Send with timeout (milliseconds). Returns :error{:timeout} if exceeded.
    process_send_timeout: struct { dest: Reg, target: Reg, handler_index: u32, args: []const Reg, timeout_ms: Reg },

    pub const BinOp = struct { dest: Reg, lhs: Reg, rhs: Reg };
    pub const UnOp = struct { dest: Reg, operand: Reg };
};

pub const Block = struct {
    id: BlockId,
    insts: std.ArrayListUnmanaged(Inst),
    alloc: std.mem.Allocator,

    pub fn init(id: BlockId, alloc: std.mem.Allocator) Block {
        return .{ .id = id, .insts = .{}, .alloc = alloc };
    }

    pub fn append(self: *Block, inst: Inst) void {
        self.insts.append(self.alloc, inst) catch {};
    }
};

pub const Function = struct {
    module: []const u8,
    name: []const u8,
    params: []const Param,
    return_type: Type,
    blocks: std.ArrayListUnmanaged(Block),
    next_reg: Reg,
    next_block: BlockId,
    alloc: std.mem.Allocator,

    pub const Param = struct {
        name: []const u8,
        type_: Type,
    };

    pub fn init(module: []const u8, name: []const u8, alloc: std.mem.Allocator) Function {
        return .{
            .module = module,
            .name = name,
            .params = &.{},
            .return_type = .void,
            .blocks = .{},
            .next_reg = 0,
            .next_block = 0,
            .alloc = alloc,
        };
    }

    /// Allocate a new virtual register.
    pub fn newReg(self: *Function) Reg {
        const r = self.next_reg;
        self.next_reg += 1;
        return r;
    }

    /// Create a new basic block and return it.
    pub fn newBlock(self: *Function) *Block {
        const id = self.next_block;
        self.next_block += 1;
        self.blocks.append(self.alloc, Block.init(id, self.alloc)) catch {};
        return &self.blocks.items[self.blocks.items.len - 1];
    }

    /// Get a block by ID.
    pub fn getBlock(self: *Function, id: BlockId) *Block {
        return &self.blocks.items[id];
    }
};

pub const ProcessInfo = struct {
    name: []const u8,
    state_type: ?[]const u8 = null, // Name of the state struct type (e.g., "CounterState")
    state_fields: []const StateFieldInfo,
    handler_names: []const []const u8,
    mailbox_size: u32 = 64, // max message count (default 64)
};

pub const StateFieldInfo = struct {
    name: []const u8,
};

pub const StructFieldInfo = struct {
    name: []const u8,
    type_name: []const u8, // "int", "float", "string", "bool", or struct name
};

pub const StructInfo = struct {
    name: []const u8,
    fields: []const StructFieldInfo,
};

pub const EnumInfo = struct {
    name: []const u8,
    variants: []const []const u8,
};

pub const UnionVariantInfo = struct {
    tag: []const u8,
    has_value: bool,
    value_type: []const u8, // "int", "float", "string", "bool", or struct name
};

pub const UnionInfo = struct {
    name: []const u8,
    variants: []const UnionVariantInfo,
};

pub const Program = struct {
    functions: std.ArrayListUnmanaged(Function),
    process_decls: std.ArrayListUnmanaged(ProcessInfo),
    struct_decls: std.ArrayListUnmanaged(StructInfo),
    enum_decls: std.ArrayListUnmanaged(EnumInfo),
    union_decls: std.ArrayListUnmanaged(UnionInfo),
    test_names: std.ArrayListUnmanaged([]const u8), // "addition works"
    test_modules: std.ArrayListUnmanaged([]const u8), // "Math"
    test_fn_names: std.ArrayListUnmanaged([]const u8), // "__test_0"
    entry_module: []const u8,
    entry_function: []const u8,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Program {
        return .{
            .functions = .{},
            .process_decls = .{},
            .struct_decls = .{},
            .enum_decls = .{},
            .union_decls = .{},
            .test_names = .{},
            .test_modules = .{},
            .test_fn_names = .{},
            .entry_module = "",
            .entry_function = "main",
            .alloc = alloc,
        };
    }

    pub fn addFunction(self: *Program, func: Function) void {
        self.functions.append(self.alloc, func) catch {};
    }
};
