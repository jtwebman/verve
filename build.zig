const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "verve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the Verve compiler");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Fast tests — parser, checker, IR, runtime
    // Run with: zig build test
    const test_step = b.step("test", "Run tests");

    const fast_tests = [_][]const u8{
        "src/test_parser.zig",
        "src/test_parser_error.zig",
        "src/test_checker.zig",
        "src/test_ir.zig",
    };
    for (fast_tests) |file| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // Runtime unit tests (List, sliceFromPair, Mailbox safety checks)
    const runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/runtime/runtime.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(runtime_tests).step);

    const process_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/runtime/process.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(process_tests).step);

    // Compile pipeline tests (each invokes zig build-exe)
    // Run with: zig build test-compile
    const compile_test_step = b.step("test-compile", "Run compile pipeline tests");
    const compile_tests = [_][]const u8{
        "src/compile_test_basic.zig",
        "src/compile_test_type.zig",
        "src/compile_test_file.zig",
        "src/compile_test_string.zig",
        "src/compile_test_process.zig",
        "src/compile_test_scheduler.zig",
        "src/compile_test_env.zig",
        "src/compile_test_math.zig",
        "src/compile_test_json.zig",
        "src/compile_test_examples.zig",
    };
    for (compile_tests) |file| {
        const ct = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
            }),
        });
        compile_test_step.dependOn(&b.addRunArtifact(ct).step);
    }

    // Compile pipeline tests with ReleaseSafe (catches runtime safety violations)
    // Run with: zig build test-compile-safe
    const compile_safe_step = b.step("test-compile-safe", "Run compile tests with ReleaseSafe");
    for (compile_tests) |file| {
        const ct = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
            }),
        });
        ct.root_module.resolved_target = target;
        const run = b.addRunArtifact(ct);
        run.setEnvironmentVariable("VERVE_OPTIMIZE", "-OReleaseSafe");
        compile_safe_step.dependOn(&run.step);
    }

    // Network tests (TCP/HTTP with socket ops, ~2 min)
    // Run with: zig build test-slow
    const net_test_step = b.step("test-slow", "Run slow tests (TCP/HTTP, socket ops)");
    const net_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/compile_test_net.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    net_test_step.dependOn(&b.addRunArtifact(net_tests).step);
}
