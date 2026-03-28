const std = @import("std");

// ── Checked arithmetic (poison values) ─────────────

/// Poison sentinel values — chosen to be in the extreme negative range
/// that normal arithmetic cannot produce (i64.MIN region).
pub const POISON_OVERFLOW: i64 = std.math.minInt(i64) + 1; // 0x8000000000000001
pub const POISON_DIV_ZERO: i64 = std.math.minInt(i64) + 2;
pub const POISON_OUT_OF_BOUNDS: i64 = std.math.minInt(i64) + 3;
pub const POISON_INFINITY: i64 = std.math.minInt(i64) + 4;
pub const POISON_NAN: i64 = std.math.minInt(i64) + 5;

pub fn isPoison(v: i64) bool {
    // Poison sentinels: MIN+1 (overflow), MIN+2 (div_zero), MIN+3 (oob), MIN+4 (infinity), MIN+5 (nan)
    return v >= std.math.minInt(i64) and v <= std.math.minInt(i64) + 5 and v != std.math.minInt(i64);
}

pub fn isPoison_f64(x: f64) bool {
    const bits: i64 = @bitCast(x);
    return isPoison(bits);
}

pub fn verve_add_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) return POISON_OVERFLOW;
    return result[0];
}

pub fn verve_sub_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    const result = @subWithOverflow(a, b);
    if (result[1] != 0) return POISON_OVERFLOW;
    return result[0];
}

pub fn verve_mul_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) return POISON_OVERFLOW;
    return result[0];
}

pub fn verve_div_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    if (b == 0) return POISON_DIV_ZERO;
    return @divTrunc(a, b);
}

pub fn verve_mod_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    if (b == 0) return POISON_DIV_ZERO;
    return @mod(a, b);
}

pub fn verve_neg_checked(a: i64) i64 {
    if (isPoison(a)) return a;
    const result = @subWithOverflow(@as(i64, 0), a);
    if (result[1] != 0) return POISON_OVERFLOW;
    return result[0];
}

/// Check if a value is poison (for comparisons — poison is never equal to anything).
pub fn verve_is_poison(v: i64) i64 {
    return if (isPoison(v)) @as(i64, 1) else @as(i64, 0);
}

/// Check a float result for infinity/NaN and convert to poison.
pub fn float_check(val: i64) i64 {
    const f = f64_from_i64(val);
    if (std.math.isNan(f)) return POISON_NAN;
    if (std.math.isInf(f)) return POISON_INFINITY;
    return val;
}

/// Check a native f64 for infinity/NaN — returns poison sentinel as f64.
pub fn float_check_f64(val: f64) f64 {
    if (std.math.isNan(val)) return @bitCast(POISON_NAN);
    if (std.math.isInf(val)) return @bitCast(POISON_INFINITY);
    return val;
}

pub fn f64_from_i64(v: i64) f64 {
    return @bitCast(v);
}

pub fn i64_from_f64(v: f64) i64 {
    return @bitCast(v);
}

/// Comparison operators that return 0 (false) if either operand is poison.
pub fn verve_eq(a: i64, b: i64) i64 {
    if (isPoison(a) or isPoison(b)) return 0;
    return if (a == b) @as(i64, 1) else @as(i64, 0);
}

pub fn verve_neq(a: i64, b: i64) i64 {
    if (isPoison(a) or isPoison(b)) return 0;
    return if (a != b) @as(i64, 1) else @as(i64, 0);
}

pub fn verve_lt(a: i64, b: i64) i64 {
    if (isPoison(a) or isPoison(b)) return 0;
    return if (a < b) @as(i64, 1) else @as(i64, 0);
}

pub fn verve_gt(a: i64, b: i64) i64 {
    if (isPoison(a) or isPoison(b)) return 0;
    return if (a > b) @as(i64, 1) else @as(i64, 0);
}

pub fn verve_lte(a: i64, b: i64) i64 {
    if (isPoison(a) or isPoison(b)) return 0;
    return if (a <= b) @as(i64, 1) else @as(i64, 0);
}

pub fn verve_gte(a: i64, b: i64) i64 {
    if (isPoison(a) or isPoison(b)) return 0;
    return if (a >= b) @as(i64, 1) else @as(i64, 0);
}
