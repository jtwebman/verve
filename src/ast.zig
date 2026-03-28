const std = @import("std");

pub const Span = struct {
    start: usize,
    end: usize,
};

// File-level import
pub const FileImport = struct {
    path: []const u8,
    span: Span,
};

// Top-level declarations
pub const Decl = union(enum) {
    module_decl: ModuleDecl,
    process_decl: ProcessDecl,
    type_decl: TypeDecl,
    struct_decl: StructDecl,
};

pub const ModuleDecl = struct {
    name: []const u8,
    constants: []const Assign,
    functions: []const FnDecl,
    tests: []const TestDecl,
    imports: []const Import,
    exported: bool,
    doc_comment: ?[]const u8,
    span: Span,
};

pub const TestDecl = struct {
    name: []const u8,
    body: []const Stmt,
    span: Span,
};

pub const MemoryBudget = union(enum) {
    sized: Expr, // [memory: 64MB], [memory: 1KB], etc.
    unbounded: void, // [memory: unbounded]
};

pub const ProcessDecl = struct {
    name: []const u8,
    memory: ?MemoryBudget,
    state_type: ?[]const u8, // struct name for process state (new syntax)
    receive_handlers: []const ReceiveDecl,
    invariants: []const Expr,
    exported: bool,
    doc_comment: ?[]const u8,
    span: Span,
};

pub const TypeDecl = struct {
    name: []const u8,
    value: TypeExpr,
    exported: bool,
    span: Span,
};

pub const StructDecl = struct {
    name: []const u8,
    fields: []const Field,
    type_params: []const []const u8,
    exported: bool,
    span: Span,
};

pub const Field = struct {
    name: []const u8,
    type_expr: TypeExpr,
    default_value: ?Expr,
    span: Span,
};

pub const Import = struct {
    module_name: []const u8,
    symbols: []const []const u8,
    span: Span,
};

// Functions & receive handlers
pub const FnDecl = struct {
    name: []const u8,
    params: []const Param,
    return_type: TypeExpr,
    guards: []const Expr,
    body: []const Stmt,
    doc_comment: ?[]const u8,
    examples: []const []const u8,
    properties: []const []const u8,
    span: Span,
};

pub const ReceiveDecl = struct {
    name: []const u8,
    params: []const Param,
    return_type: TypeExpr,
    guards: []const Expr,
    body: []const Stmt,
    doc_comment: ?[]const u8,
    examples: []const []const u8,
    properties: []const []const u8,
    span: Span,
};

pub const Param = struct {
    name: []const u8,
    type_expr: TypeExpr,
    span: Span,
};

// Type expressions
pub const TypeExpr = union(enum) {
    simple: []const u8, // int, string, bool, Money, etc.
    generic: Generic, // list<T>, map<K, V>, Result<T>, process<Ledger>
    optional: *const TypeExpr, // Account?
    enum_type: []const []const u8, // enum { USD, EUR, GBP }
    union_type: []const UnionVariant, // union { :ok { value: T }; :error { reason: string }; }
    fn_type: FnType, // fn(int, int) -> bool
};

pub const FnType = struct {
    params: []const TypeExpr,
    return_type: *const TypeExpr,
};

pub const Generic = struct {
    name: []const u8,
    args: []const TypeExpr,
};

pub const UnionVariant = struct {
    tag: []const u8,
    fields: []const Field,
};

// Statements
pub const Stmt = union(enum) {
    assign: Assign,
    field_assign: FieldAssign, // state.field = expr;
    append: Append,
    match_stmt: MatchStmt,
    if_stmt: IfStmt,
    while_stmt: WhileStmt,
    send_stmt: SendStmt,
    tell_stmt: TellStmt,
    return_stmt: ReturnStmt,
    break_stmt: Span,
    continue_stmt: Span,
    receive_stmt: Span, // receive; — block and process one message
    watch_stmt: WatchStmt,
    assert_stmt: AssertStmt,
    expr_stmt: Expr,
};

pub const WatchStmt = struct {
    target: Expr,
    span: Span,
};

pub const Assign = struct {
    name: []const u8,
    type_expr: ?TypeExpr, // null for reassignment, set for declaration
    value: Expr,
    span: Span,
};

pub const FieldAssign = struct {
    target: Expr, // field_access expression (e.g., state.count)
    value: Expr,
    span: Span,
};

pub const Append = struct {
    target: Expr,
    value: Expr,
    span: Span,
};

pub const MatchStmt = struct {
    subject: Expr,
    arms: []const MatchArm,
    span: Span,
};

pub const MatchArm = struct {
    pattern: Pattern,
    body: []const Stmt,
};

pub const Pattern = union(enum) {
    tag: TagPattern, // :ok{value}
    literal: Expr, // true, false, 42, "hello"
    wildcard: void, // _
};

pub const TagPattern = struct {
    tag: []const u8,
    bindings: []const []const u8,
};

pub const IfStmt = struct {
    condition: Expr,
    body: []const Stmt,
    else_body: ?[]const Stmt,
    span: Span,
};

pub const WhileStmt = struct {
    condition: Expr,
    body: []const Stmt,
    span: Span,
};

pub const SendStmt = struct {
    target: Expr,
    handler: []const u8,
    args: []const Expr,
    timeout: Expr,
    span: Span,
};

pub const TellStmt = struct {
    target: Expr,
    handler: []const u8,
    args: []const Expr,
    span: Span,
};

pub const AssertStmt = struct {
    condition: Expr,
    message: ?[]const u8,
    span: Span,
};

pub const ReturnStmt = struct {
    value: ?Expr,
    span: Span,
};

// Expressions
pub const Expr = union(enum) {
    int_literal: i64,
    float_literal: f64,
    string_literal: []const u8,
    bool_literal: bool,
    identifier: []const u8,
    tag: []const u8, // :ok, :error, :USD
    tagged_value: TaggedValue, // :ok{42}, :circle{5.0}
    field_access: FieldAccess,
    index_access: IndexAccess,
    binary_op: BinaryOp,
    unary_op: UnaryOp,
    call: Call,
    struct_literal: StructLiteral,
    string_interp: StringInterp,
    match_expr: *const MatchStmt,
    none_literal: void,
    void_literal: void,
};

pub const TaggedValue = struct {
    tag: []const u8,
    value: ?*const Expr, // null for bare tag variants like :red{}
};

pub const FieldAccess = struct {
    target: *const Expr,
    field: []const u8,
};

pub const IndexAccess = struct {
    target: *const Expr,
    index: *const Expr,
};

pub const BinaryOp = struct {
    op: Op,
    left: *const Expr,
    right: *const Expr,
};

pub const UnaryOp = struct {
    op: Op,
    operand: *const Expr,
};

pub const Op = enum {
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    neq,
    lt,
    gt,
    lte,
    gte,
    @"and",
    @"or",
    not,
};

pub const Call = struct {
    target: *const Expr,
    args: []const Expr,
};

pub const StructLiteral = struct {
    name: []const u8,
    fields: []const StructLiteralField,
};

pub const StringInterp = struct {
    parts: []const StringInterpPart,
};

pub const StringInterpPart = union(enum) {
    literal: []const u8,
    expr: Expr,
};

pub const StructLiteralField = struct {
    name: []const u8,
    value: Expr,
};

// The root of a parsed .vv file
pub const File = struct {
    imports: []const FileImport,
    decls: []const Decl,
};
