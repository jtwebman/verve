const std = @import("std");
const checked = @import("checked.zig");

// ── Math (int) ───────────────────────────────────

pub fn math_abs(x: i64) i64 {
    if (x == std.math.minInt(i64)) return checked.POISON_OVERFLOW;
    return if (x < 0) -x else x;
}

pub fn math_min(a: i64, b: i64) i64 {
    return if (a < b) a else b;
}

pub fn math_max(a: i64, b: i64) i64 {
    return if (a > b) a else b;
}

pub fn math_clamp(x: i64, lo: i64, hi: i64) i64 {
    return if (x < lo) lo else if (x > hi) hi else x;
}

pub fn math_pow(base: i64, exp: i64) i64 {
    if (exp < 0) return 0;
    var result: i64 = 1;
    var e: i64 = exp;
    var b: i64 = base;
    while (e > 0) {
        if (@mod(e, 2) == 1) result = result *% b;
        b = b *% b;
        e = @divTrunc(e, 2);
    }
    return result;
}

pub fn math_sqrt(x: i64) i64 {
    if (x <= 0) return 0;
    const f: f64 = @floatFromInt(x);
    return @intFromFloat(@sqrt(f));
}

pub fn math_log2(x: i64) i64 {
    if (x <= 0) return 0;
    var n: i64 = x;
    var result: i64 = 0;
    while (n > 1) {
        n = @divTrunc(n, 2);
        result += 1;
    }
    return result;
}

// ── Math (float) ──────────────────────────────────

pub fn math_abs_f(x: f64) f64 {
    return @abs(x);
}

pub fn math_floor(x: f64) i64 {
    if (checked.isPoison_f64(x) or std.math.isNan(x)) return checked.POISON_NAN;
    return @intFromFloat(@floor(x));
}

pub fn math_ceil(x: f64) i64 {
    if (checked.isPoison_f64(x) or std.math.isNan(x)) return checked.POISON_NAN;
    return @intFromFloat(@ceil(x));
}

pub fn math_round(x: f64) i64 {
    if (checked.isPoison_f64(x) or std.math.isNan(x)) return checked.POISON_NAN;
    return @intFromFloat(@round(x));
}

pub fn math_sin(x: f64) f64 {
    return @sin(x);
}

pub fn math_cos(x: f64) f64 {
    return @cos(x);
}

pub fn math_tan(x: f64) f64 {
    return @tan(x);
}

pub fn math_sqrt_f(x: f64) f64 {
    if (x < 0) return 0.0;
    return @sqrt(x);
}

pub fn math_pow_f(base: f64, exp: f64) f64 {
    return std.math.pow(f64, base, exp);
}

pub fn math_log(x: f64) f64 {
    if (x <= 0) return 0.0;
    return @log(x);
}

pub fn math_log10(x: f64) f64 {
    if (x <= 0) return 0.0;
    return @log10(x);
}

pub fn math_exp(x: f64) f64 {
    return @exp(x);
}

pub fn math_min_f(a: f64, b: f64) f64 {
    return if (a < b) a else b;
}

pub fn math_max_f(a: f64, b: f64) f64 {
    return if (a > b) a else b;
}
