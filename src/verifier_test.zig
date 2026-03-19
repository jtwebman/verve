const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Interpreter = @import("interpreter.zig").Interpreter;
const Verifier = @import("verifier.zig").Verifier;
const testing = std.testing;

fn runVerifier(source: []const u8) !@import("verifier.zig").VerifyResult {
    const alloc = std.heap.page_allocator;
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var interp = Interpreter.init(alloc);
    try interp.load(file);
    var verifier = Verifier.init(alloc, &interp);
    return try verifier.verify(file);
}

// ── VALID ─────────────────────────────────────────────────

test "VALID: all examples pass" {
    const result = try runVerifier(
        \\module Math {
        \\    /// @example add(2, 3) == 5
        \\    /// @example add(0, 0) == 0
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 2), result.examples_passed);
    try testing.expectEqual(@as(usize, 0), result.examples_failed);
}

test "VALID: multiple functions all pass" {
    const result = try runVerifier(
        \\module Math {
        \\    /// @example add(1, 2) == 3
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\    /// @example mul(3, 4) == 12
        \\    fn mul(a: int, b: int) -> int {
        \\        return a * b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 2), result.examples_passed);
    try testing.expectEqual(@as(usize, 0), result.examples_failed);
}

test "VALID: example with tag result" {
    const result = try runVerifier(
        \\module Test {
        \\    /// @example get_tag() == :ok
        \\    fn get_tag() -> string {
        \\        return :ok;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 1), result.examples_passed);
}

test "VALID: example with boolean result" {
    const result = try runVerifier(
        \\module Test {
        \\    /// @example is_positive(5) == true
        \\    /// @example is_positive(0) == false
        \\    fn is_positive(x: int) -> bool {
        \\        return x > 0;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 2), result.examples_passed);
    try testing.expectEqual(@as(usize, 0), result.examples_failed);
}

// ── INVALID ───────────────────────────────────────────────

test "INVALID: wrong result" {
    const result = try runVerifier(
        \\module Math {
        \\    /// @example add(2, 3) == 999
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 0), result.examples_passed);
    try testing.expectEqual(@as(usize, 1), result.examples_failed);
    try testing.expectEqualStrings("add", result.failures.items[0].function);
}

test "INVALID: one passes one fails" {
    const result = try runVerifier(
        \\module Math {
        \\    /// @example add(2, 3) == 5
        \\    /// @example add(10, 20) == 999
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 1), result.examples_passed);
    try testing.expectEqual(@as(usize, 1), result.examples_failed);
}

// ── INCOMPLETE ────────────────────────────────────────────

test "INCOMPLETE: no examples" {
    const result = try runVerifier(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 0), result.examples_passed);
    try testing.expectEqual(@as(usize, 0), result.examples_failed);
}

test "INCOMPLETE: doc comment but no @example" {
    const result = try runVerifier(
        \\module Math {
        \\    /// Adds two numbers
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 0), result.examples_passed);
    try testing.expectEqual(@as(usize, 0), result.examples_failed);
}

// ── Edge cases ────────────────────────────────────────────

test "VALID: example with string result" {
    const result = try runVerifier(
        \\module Test {
        \\    /// @example greet() == "hello"
        \\    fn greet() -> string {
        \\        return "hello";
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 1), result.examples_passed);
}

// ── Properties ────────────────────────────────────────────

test "VALID: property passes for all inputs" {
    const result = try runVerifier(
        \\module Math {
        \\    /// @property fn(a, b) { a + b == b + a }
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 1), result.properties_passed);
    try testing.expectEqual(@as(usize, 0), result.properties_failed);
}

test "VALID: property with single param" {
    const result = try runVerifier(
        \\module Math {
        \\    /// @property fn(x) { x * 0 == 0 }
        \\    fn zero_mul(x: int) -> int {
        \\        return x * 0;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 1), result.properties_passed);
}

test "VALID: examples and properties together" {
    const result = try runVerifier(
        \\module Math {
        \\    /// @example add(2, 3) == 5
        \\    /// @property fn(a, b) { a + b == b + a }
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 1), result.examples_passed);
    try testing.expectEqual(@as(usize, 1), result.properties_passed);
}

test "INVALID: property fails" {
    const result = try runVerifier(
        \\module Math {
        \\    /// @property fn(a, b) { a - b == b - a }
        \\    fn sub(a: int, b: int) -> int {
        \\        return a - b;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    // a - b != b - a (unless a == b)
    try testing.expectEqual(@as(usize, 0), result.properties_passed);
    try testing.expectEqual(@as(usize, 1), result.properties_failed);
}

// ── Edge cases ────────────────────────────────────────────

test "VALID: example with zero" {
    const result = try runVerifier(
        \\module Test {
        \\    /// @example zero() == 0
        \\    fn zero() -> int {
        \\        return 0;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
    try testing.expectEqual(@as(usize, 1), result.examples_passed);
}
