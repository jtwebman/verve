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

    const test_step = b.step("test", "Run tests");

    // Parser tests
    const parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parser_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(parser_tests).step);

    // Parser error tests
    const parser_error_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parser_error_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(parser_error_tests).step);

    // Checker tests
    const checker_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/checker_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(checker_tests).step);

    // Compile pipeline tests (AST → IR → Zig → binary → run → verify)
    // Split into 6 files with unique temp paths so they can run in parallel.
    const compile_test_files = [_][]const u8{
        "src/compile_test_basic.zig",
        "src/compile_test_string.zig",
        "src/compile_test_process.zig",
        "src/compile_test_math.zig",
        "src/compile_test_json.zig",
        "src/compile_test_net.zig",
    };
    for (compile_test_files) |file| {
        const ct = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&b.addRunArtifact(ct).step);
    }
}
