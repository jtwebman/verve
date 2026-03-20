const std = @import("std");

/// Verve IR — typed, SSA-style intermediate representation.
/// Each instruction produces a value identified by an index.
/// Types are monomorphized: an int is a bare i64, not a tagged union.

// ── Types ────────────────────────────────────────────────

pub const Type = enum {
    i64,
    f64,
    bool,
    string, // pointer + length
    void,
    // Future: struct types, list<T>, map<K,V>, process_id, etc.
};

// ── Instructions ─────────────────────────────────────────

/// A register (SSA value). Instructions produce registers, instructions consume registers.
pub const Reg = u32;

pub const Inst = union(enum) {
    // ── Constants
    const_int: struct { dest: Reg, value: i64 },
    const_float: struct { dest: Reg, value: f64 },
    const_bool: struct { dest: Reg, value: bool },
    const_string: struct { dest: Reg, value: []const u8 },

    // ── Arithmetic (i64)
    add_i64: BinOp,
    sub_i64: BinOp,
    mul_i64: BinOp,
    div_i64: BinOp,
    mod_i64: BinOp,
    neg_i64: UnOp,

    // ── Arithmetic (f64)
    add_f64: BinOp,
    sub_f64: BinOp,
    mul_f64: BinOp,
    div_f64: BinOp,
    neg_f64: UnOp,

    // ── Comparison
    eq: BinOp,
    neq: BinOp,
    lt_i64: BinOp,
    gt_i64: BinOp,
    lte_i64: BinOp,
    gte_i64: BinOp,
    lt_f64: BinOp,
    gt_f64: BinOp,
    lte_f64: BinOp,
    gte_f64: BinOp,

    // ── Logical
    and_bool: BinOp,
    or_bool: BinOp,
    not_bool: UnOp,

    // ── String
    concat_string: BinOp,

    // ── Variables
    load_local: struct { dest: Reg, name: []const u8 },
    store_local: struct { name: []const u8, src: Reg },

    // ── Control flow
    jump: struct { target: BlockId },
    branch: struct { cond: Reg, then_block: BlockId, else_block: BlockId },
    ret: struct { value: ?Reg },
    ret_void: void,

    // ── Function calls
    call: struct {
        dest: Reg,
        module: []const u8,
        function: []const u8,
        args: []const Reg,
    },
    call_builtin: struct {
        dest: Reg,
        name: []const u8,
        args: []const Reg,
    },

    // ── Printing (temporary — will become a call to runtime)
    print: struct { args: []const Reg, newline: bool },

    pub const BinOp = struct { dest: Reg, lhs: Reg, rhs: Reg };
    pub const UnOp = struct { dest: Reg, operand: Reg };
};

pub const BlockId = u32;

// ── Basic Block ──────────────────────────────────────────

pub const Block = struct {
    id: BlockId,
    insts: std.ArrayListUnmanaged(Inst),
};

// ── Function ─────────────────────────────────────────────

pub const Function = struct {
    module: []const u8,
    name: []const u8,
    params: []const Param,
    return_type: Type,
    blocks: std.ArrayListUnmanaged(Block),
    next_reg: Reg,

    pub const Param = struct {
        name: []const u8,
        type_: Type,
    };
};

// ── Module ───────────────────────────────────────────────

pub const Module = struct {
    name: []const u8,
    functions: std.ArrayListUnmanaged(Function),
    constants: std.ArrayListUnmanaged(Constant),
};

pub const Constant = struct {
    name: []const u8,
    type_: Type,
    value: ConstValue,
};

pub const ConstValue = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
};

// ── Program ──────────────────────────────────────────────

pub const Program = struct {
    modules: std.ArrayListUnmanaged(Module),
    entry_module: []const u8,
    entry_function: []const u8,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Program {
        return .{
            .modules = .{},
            .entry_module = "",
            .entry_function = "main",
            .alloc = alloc,
        };
    }
};
