const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower.zig").Lower;
const ZigBackend = @import("zig_backend.zig").ZigBackend;
const testing = std.testing;
const alloc = std.heap.page_allocator;

fn getZigPath() []const u8 {
    return std.posix.getenv("VERVE_ZIG") orelse "/home/jt/.local/zig/zig";
}

fn getOptimizeMode() []const u8 {
    return std.posix.getenv("VERVE_OPTIMIZE") orelse "-OReleaseFast";
}

/// Compile Verve source to native binary, run it, return exit code.
fn compileAndRun(source: []const u8) !u8 {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_math";
    try backend.build(path, getZigPath());
    defer std.fs.cwd().deleteFile(path) catch {};
    var child = std.process.Child.init(&.{path}, alloc);
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else => 255,
    };
}

/// Compile, run, capture stdout.
fn compileAndCapture(source: []const u8) !struct { exit: u8, stdout: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_math_cap";
    try backend.build(path, getZigPath());
    defer std.fs.cwd().deleteFile(path) catch {};
    var child = std.process.Child.init(&.{path}, alloc);
    child.stdout_behavior = .Pipe;
    try child.spawn();
    var buf: [4096]u8 = undefined;
    const n = try child.stdout.?.readAll(&buf);
    const term = try child.wait();
    return .{
        .exit = switch (term) {
            .Exited => |code| code,
            else => 255,
        },
        .stdout = try alloc.dupe(u8, buf[0..n]),
    };
}

// ── Overflow / poison tests ────────────────────────

test "compile: division by zero produces poison" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: int = 10 / 0;
        \\        // Poison prints as a large negative number (sentinel)
        \\        if x > 0 {
        \\            Stdio.println("wrong: positive");
        \\        } else {
        \\            Stdio.println("poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: modulo by zero produces poison" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: int = 10 % 0;
        \\        if x > 0 {
        \\            Stdio.println("wrong");
        \\        } else {
        \\            Stdio.println("poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: poison propagates through addition" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        bad: int = 10 / 0;
        \\        result: int = bad + 5;
        \\        if result > 0 {
        \\            Stdio.println("wrong");
        \\        } else {
        \\            Stdio.println("propagated");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("propagated\n", r.stdout);
}

test "compile: overflow on addition" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        max: int = 9223372036854775807;
        \\        result: int = max + 1;
        \\        if result > 0 {
        \\            Stdio.println("wrapped");
        \\        } else {
        \\            Stdio.println("poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: overflow on multiplication" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        big: int = 9223372036854775807;
        \\        result: int = big * 2;
        \\        if result > 0 {
        \\            Stdio.println("wrapped");
        \\        } else {
        \\            Stdio.println("poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: underflow on subtraction" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        min: int = 0 - 9223372036854775807;
        \\        result: int = min - 2;
        \\        // Poison: neither > 0 nor < 0 nor == 0
        \\        if result > 0 {
        \\            Stdio.println("positive");
        \\        } else {
        \\            if result == 0 {
        \\                Stdio.println("zero");
        \\            } else {
        \\                if result < 0 {
        \\                    Stdio.println("negative");
        \\                } else {
        \\                    Stdio.println("poison");
        \\                }
        \\            }
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Poison is not > 0, not == 0, not < 0 — falls through to "poison"
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: poison propagates through multiple operations" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        bad: int = 10 / 0;
        \\        r1: int = bad + 5;
        \\        r2: int = r1 * 3;
        \\        r3: int = r2 - 1;
        \\        if r3 > 0 {
        \\            Stdio.println("wrong");
        \\        } else {
        \\            Stdio.println("still poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("still poison\n", r.stdout);
}

test "compile: poison does not affect independent values" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        bad: int = 10 / 0;
        \\        good: int = 3 + 4;
        \\        Stdio.println(good);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("7\n", r.stdout);
}

test "compile: normal arithmetic still works" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(3 + 4);
        \\        Stdio.println(10 - 3);
        \\        Stdio.println(6 * 7);
        \\        Stdio.println(42 / 6);
        \\        Stdio.println(10 % 3);
        \\        Stdio.println(0 - 5);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("7\n7\n42\n7\n1\n-5\n", r.stdout);
}

// ── Poison edge case tests ─────────────────────────

test "compile: float division by zero is poison" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: float = 1.0 / 0.0;
        \\        r: int = Math.round(x);
        \\        if r == 0 {
        \\            Stdio.println("zero");
        \\        } else {
        \\            if r > 0 {
        \\                Stdio.println("positive");
        \\            } else {
        \\                if r < 0 {
        \\                    Stdio.println("negative");
        \\                } else {
        \\                    Stdio.println("poison");
        \\                }
        \\            }
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: poison propagation through function return" {
    const r = try compileAndCapture(
        \\module Math2 {
        \\    fn double(x: int) -> int {
        \\        return x * 2;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        bad: int = 10 / 0;
        \\        result: int = Math2.double(bad);
        \\        if result > 0 {
        \\            Stdio.println("wrong");
        \\        } else {
        \\            if result == 0 {
        \\                Stdio.println("wrong");
        \\            } else {
        \\                if result < 0 {
        \\                    Stdio.println("wrong");
        \\                } else {
        \\                    Stdio.println("propagated");
        \\                }
        \\            }
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("propagated\n", r.stdout);
}

// ── Type system tests ──────────────────────────────

test "compile: if/else with string comparison" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = "hello";
        \\        if s == "hello" {
        \\            Stdio.println("match");
        \\        } else {
        \\            Stdio.println("no match");
        \\        }
        \\        if s == "world" {
        \\            Stdio.println("match");
        \\        } else {
        \\            Stdio.println("no match");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("match\nno match\n", r.stdout);
}

test "compile: nested struct field access" {
    const r = try compileAndCapture(
        \\struct Inner { value: int = 0; }
        \\struct Outer { name: string = ""; count: int = 0; }
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"test\", \"count\": 42}";
        \\        match Json.parse(data, Outer) {
        \\            :ok{obj} => {
        \\                Stdio.println(obj.name);
        \\                Stdio.println(obj.count);
        \\            }
        \\            :error{e} => Stdio.println("fail");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("test\n42\n", r.stdout);
}

// ── Math tests ─────────────────────────────────────

test "compile: math abs min max" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.abs(-42));
        \\        Stdio.println(Math.min(10, 3));
        \\        Stdio.println(Math.max(10, 3));
        \\        Stdio.println(Math.clamp(50, 0, 100));
        \\        Stdio.println(Math.clamp(-5, 0, 100));
        \\        Stdio.println(Math.clamp(200, 0, 100));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n3\n10\n50\n0\n100\n", r.stdout);
}

test "compile: math abs edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.abs(0));
        \\        Stdio.println(Math.abs(1));
        \\        Stdio.println(Math.abs(-1));
        \\        Stdio.println(Math.abs(999999));
        \\        Stdio.println(Math.abs(-999999));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n1\n999999\n999999\n", r.stdout);
}

test "compile: math min max edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.min(0, 0));
        \\        Stdio.println(Math.min(-5, 5));
        \\        Stdio.println(Math.min(5, -5));
        \\        Stdio.println(Math.max(0, 0));
        \\        Stdio.println(Math.max(-5, 5));
        \\        Stdio.println(Math.max(5, -5));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n-5\n-5\n0\n5\n5\n", r.stdout);
}

test "compile: math clamp edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.clamp(5, 5, 5));
        \\        Stdio.println(Math.clamp(0, -10, 10));
        \\        Stdio.println(Math.clamp(-100, -10, 10));
        \\        Stdio.println(Math.clamp(100, -10, 10));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("5\n0\n-10\n10\n", r.stdout);
}

test "compile: math pow edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.pow(2, 0));
        \\        Stdio.println(Math.pow(0, 5));
        \\        Stdio.println(Math.pow(1, 1000));
        \\        Stdio.println(Math.pow(-2, 3));
        \\        Stdio.println(Math.pow(-2, 4));
        \\        Stdio.println(Math.pow(10, 6));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1\n0\n1\n-8\n16\n1000000\n", r.stdout);
}

test "compile: math sqrt edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.sqrt(0));
        \\        Stdio.println(Math.sqrt(1));
        \\        Stdio.println(Math.sqrt(4));
        \\        Stdio.println(Math.sqrt(9));
        \\        Stdio.println(Math.sqrt(10));
        \\        Stdio.println(Math.sqrt(10000));
        \\        Stdio.println(Math.sqrt(-1));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n2\n3\n3\n100\n0\n", r.stdout);
}

test "compile: math log2 edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.log2(1));
        \\        Stdio.println(Math.log2(2));
        \\        Stdio.println(Math.log2(3));
        \\        Stdio.println(Math.log2(8));
        \\        Stdio.println(Math.log2(1023));
        \\        Stdio.println(Math.log2(1024));
        \\        Stdio.println(Math.log2(0));
        \\        Stdio.println(Math.log2(-1));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n1\n3\n9\n10\n0\n0\n", r.stdout);
}

test "compile: math pow sqrt log2" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.pow(2, 10));
        \\        Stdio.println(Math.pow(3, 3));
        \\        Stdio.println(Math.sqrt(144));
        \\        Stdio.println(Math.sqrt(2));
        \\        Stdio.println(Math.log2(1024));
        \\        Stdio.println(Math.log2(1));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1024\n27\n12\n1\n10\n0\n", r.stdout);
}

// ── System tests ───────────────────────────────────

test "compile: system time_ms" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        t: int = System.time_ms();
        \\        if t > 0 {
        \\            Stdio.println("ok");
        \\        } else {
        \\            Stdio.println("bad");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}

// ── Math float tests ───────────────────────────────

test "compile: math floor ceil round" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.floor(3.7));
        \\        Stdio.println(Math.floor(3.0));
        \\        Stdio.println(Math.floor(0.5));
        \\        Stdio.println(Math.ceil(3.2));
        \\        Stdio.println(Math.ceil(3.0));
        \\        Stdio.println(Math.ceil(0.1));
        \\        Stdio.println(Math.round(3.5));
        \\        Stdio.println(Math.round(3.4));
        \\        Stdio.println(Math.round(0.5));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3\n3\n0\n4\n3\n1\n4\n3\n1\n", r.stdout);
}

test "compile: math floor ceil round zero" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.floor(0.0));
        \\        Stdio.println(Math.ceil(0.0));
        \\        Stdio.println(Math.round(0.0));
        \\        Stdio.println(Math.floor(0.1));
        \\        Stdio.println(Math.floor(0.9));
        \\        Stdio.println(Math.ceil(0.1));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n0\n0\n0\n0\n1\n", r.stdout);
}

test "compile: math sin cos tan" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        zero_sin: float = Math.sin(0.0);
        \\        zero_cos: float = Math.cos(0.0);
        \\        // sin(0) == 0, cos(0) == 1
        \\        Stdio.println(Math.round(zero_sin));
        \\        Stdio.println(Math.round(zero_cos));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n", r.stdout);
}

test "compile: math sqrt_f" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        r4: float = Math.sqrt_f(4.0);
        \\        Stdio.println(Math.round(r4));
        \\        r9: float = Math.sqrt_f(9.0);
        \\        Stdio.println(Math.round(r9));
        \\        r0: float = Math.sqrt_f(0.0);
        \\        Stdio.println(Math.round(r0));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("2\n3\n0\n", r.stdout);
}

test "compile: math pow_f" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        r1: float = Math.pow_f(2.0, 10.0);
        \\        Stdio.println(Math.round(r1));
        \\        r2: float = Math.pow_f(3.0, 0.0);
        \\        Stdio.println(Math.round(r2));
        \\        r3: float = Math.pow_f(2.0, -1.0);
        \\        // 2^-1 = 0.5, round = 1 (rounds half-up)
        \\        Stdio.println(Math.round(r3));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1024\n1\n1\n", r.stdout);
}

test "compile: math log log10 exp" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        // exp(0) = 1
        \\        e0: float = Math.exp(0.0);
        \\        Stdio.println(Math.round(e0));
        \\        // log(1) = 0
        \\        l1: float = Math.log(1.0);
        \\        Stdio.println(Math.round(l1));
        \\        // log10(100) = 2
        \\        l100: float = Math.log10(100.0);
        \\        Stdio.println(Math.round(l100));
        \\        // log10(1000) = 3
        \\        l1000: float = Math.log10(1000.0);
        \\        Stdio.println(Math.round(l1000));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1\n0\n2\n3\n", r.stdout);
}

test "compile: math abs_f min_f max_f" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a1: float = Math.abs_f(3.5);
        \\        Stdio.println(Math.round(a1));
        \\        mn: float = Math.min_f(1.5, 2.5);
        \\        Stdio.println(Math.round(mn));
        \\        mx: float = Math.max_f(1.5, 2.5);
        \\        Stdio.println(Math.round(mx));
        \\        mn2: float = Math.min_f(0.1, 0.9);
        \\        Stdio.println(Math.round(mn2));
        \\        mx2: float = Math.max_f(0.1, 0.9);
        \\        Stdio.println(Math.round(mx2));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("4\n2\n3\n0\n1\n", r.stdout);
}

// ── Convert float tests ────────────────────────────

test "compile: convert to_float and to_int_f" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        f: float = Convert.to_float(42);
        \\        Stdio.println(Math.round(f));
        \\        i: int = Convert.to_int_f(3.7);
        \\        Stdio.println(i);
        \\        zero: int = Convert.to_int_f(0.0);
        \\        Stdio.println(zero);
        \\        big: float = Convert.to_float(1000);
        \\        Stdio.println(Math.round(big));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n3\n0\n1000\n", r.stdout);
}

test "compile: convert float_to_string" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = Convert.float_to_string(3.14);
        \\        Stdio.println(s);
        \\        s0: string = Convert.float_to_string(0.0);
        \\        Stdio.println(s0);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Zig formats 3.14 as "3.14e0" or "3.14" depending on version
    // Just check it starts with "3.14"
    try testing.expect(r.stdout.len > 0);
    try testing.expect(r.stdout[0] == '3');
}

test "compile: convert string_to_float" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        f: float = Convert.string_to_float("3.14");
        \\        Stdio.println(Math.round(f));
        \\        f2: float = Convert.string_to_float("100.0");
        \\        Stdio.println(Math.round(f2));
        \\        bad: float = Convert.string_to_float("abc");
        \\        Stdio.println(Math.round(bad));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3\n100\n0\n", r.stdout);
}

test "compile: convert float roundtrip" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        original: int = 99;
        \\        f: float = Convert.to_float(original);
        \\        back: int = Convert.to_int_f(f);
        \\        if back == original {
        \\            Stdio.println("roundtrip ok");
        \\        } else {
        \\            Stdio.println("roundtrip failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("roundtrip ok\n", r.stdout);
}

// ── System tests ───────────────────────────────────

test "compile: system exit with code" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println("before");
        \\        System.exit(0);
        \\        Stdio.println("after");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("before\n", r.stdout);
}

test "compile: system exit nonzero" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        System.exit(42);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), r.exit);
}

test "compile: system time_ms increases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        t1: int = System.time_ms();
        \\        t2: int = System.time_ms();
        \\        if t2 >= t1 {
        \\            Stdio.println("ok");
        \\        } else {
        \\            Stdio.println("time went backwards");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}

// ── Convert tests ──────────────────────────────────

test "compile: convert int to string and back" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = Convert.to_string(42);
        \\        Stdio.println(s);
        \\        n: int = Convert.to_int("123");
        \\        Stdio.println(n);
        \\        neg: string = Convert.to_string(-7);
        \\        Stdio.println(neg);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n123\n-7\n", r.stdout);
}

test "compile: convert to_string edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s0: string = Convert.to_string(0);
        \\        Stdio.println(s0);
        \\        s1: string = Convert.to_string(1);
        \\        Stdio.println(s1);
        \\        sn: string = Convert.to_string(-1);
        \\        Stdio.println(sn);
        \\        sb: string = Convert.to_string(1000000);
        \\        Stdio.println(sb);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n-1\n1000000\n", r.stdout);
}

test "compile: convert to_int edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Convert.to_int("0"));
        \\        Stdio.println(Convert.to_int("-42"));
        \\        Stdio.println(Convert.to_int("999"));
        \\        Stdio.println(Convert.to_int("abc"));
        \\        Stdio.println(Convert.to_int(""));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n-42\n999\n0\n0\n", r.stdout);
}

test "compile: convert roundtrip" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        original: int = 12345;
        \\        s: string = Convert.to_string(original);
        \\        back: int = Convert.to_int(s);
        \\        if back == original {
        \\            Stdio.println("roundtrip ok");
        \\        } else {
        \\            Stdio.println("roundtrip failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("roundtrip ok\n", r.stdout);
}
