const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose module
    const mod = b.addModule("zig-hll", .{
        .root_source_file = b.path("src/hll.zig"),
    });

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("zig-hll", mod);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // Example executable
    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("zig-hll", mod);

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run example to see HyperLogLog in action");
    example_step.dependOn(&run_example.step);

    // Benchmarks
    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = b.path("tests/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    benchmark.root_module.addImport("zig-hll", mod);

    const run_benchmark = b.addRunArtifact(benchmark);
    const benchmark_step = b.step("benchmark", "Run performance benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);

    // Documentation
    const docs = b.addStaticLibrary(.{
        .name = "zig-hll",
        .root_source_file = b.path("src/hll.zig"),
        .target = target,
        .optimize = optimize,
    });

    const docs_step = b.step("docs", "Generate documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
