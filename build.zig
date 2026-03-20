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

    // Process tests
    const process_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/process_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(process_tests).step);

    // Checker tests
    const checker_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/checker_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(checker_tests).step);

    // Verifier tests
    const verifier_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/verifier_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(verifier_tests).step);

    // Interpreter tests
    const interp_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/interpreter_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(interp_tests).step);

    // x86 assembler tests
    const x86_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/x86_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(x86_tests).step);

    // ELF emitter tests
    const elf_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/elf_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(elf_tests).step);
}
