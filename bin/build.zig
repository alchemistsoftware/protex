const std = @import("std");

pub fn build(B: *std.Build) void {
    const Target = B.standardTargetOptions(.{});
    const Optimize = B.standardOptimizeOption(.{});

    // Protex lib

    const Protex = B.addStaticLibrary(.{
        .name="protex",
        .root_source_file = .{.path = "../protex.zig"},
        .target = Target,
        .optimize = Optimize,
    });
    Protex.addIncludePath("../");
    Protex.addIncludePath("/usr/include/hs/");
    Protex.addIncludePath("/usr/include/python3.11");
    Protex.linkSystemLibrary("python3.11");
    Protex.linkSystemLibrary("pthread");
    Protex.linkSystemLibrary("dl");
    Protex.linkSystemLibrary("util");
    Protex.linkSystemLibrary("m");
    Protex.linkSystemLibrary("hs_runtime");
    Protex.linkLibC();
    Protex.setOutputDir("../../build");
    Protex.install();

    // Packager

    const Packager = B.addExecutable(.{
        .name = "packager",
        .root_source_file = .{.path = "../packager.zig"},
        .target = Target,
        .optimize = Optimize,
    });
    Packager.addIncludePath("/usr/include/hs/");
    Packager.linkSystemLibraryName("hs");
    Packager.linkLibC();
    Packager.setOutputDir("../../build");
    Packager.install();

    // C API Check exe

    const CapiIO = B.addExecutable(.{
        .name = "capi_io",
        .target = Target,
        .optimize = Optimize,
    });
    CapiIO.linkLibC();
    CapiIO.linkLibrary(Protex);
    CapiIO.addCSourceFiles(&.{"../capi_io.c",}, &.{"-g",});
    CapiIO.setOutputDir("../../build");
    CapiIO.install();

    // Protex lib tests

    const ProtexTests = B.addTest(.{
        .root_source_file = .{.path = "../protex.zig"},
        .target = Target,
        .optimize = Optimize
    });
    ProtexTests.addIncludePath("/usr/include/hs/");
    ProtexTests.addIncludePath("../");
    ProtexTests.addIncludePath("/usr/include/python3.11");
    ProtexTests.linkSystemLibrary("python3.11");
    ProtexTests.linkSystemLibrary("pthread");
    ProtexTests.linkSystemLibrary("dl");
    ProtexTests.linkSystemLibrary("util");
    ProtexTests.linkSystemLibrary("m");
    ProtexTests.linkSystemLibrary("hs_runtime");
    ProtexTests.linkLibC();

    // Slab allocator tests

    const SlabaTests = B.addTest(.{
        .root_source_file = .{.path = "../slab_allocator.zig"},
        .target = Target,
        .optimize = Optimize
    });

    // Sempy tests

    const SempyTests = B.addTest(.{
        .root_source_file = .{.path = "../sempy.zig"},
        .target = Target,
        .optimize = Optimize
    });
    SempyTests.addIncludePath("/usr/include/python3.11");
    SempyTests.linkSystemLibrary("python3.11");
    SempyTests.linkSystemLibrary("pthread");
    SempyTests.linkSystemLibrary("dl");
    SempyTests.linkSystemLibrary("util");
    SempyTests.linkSystemLibrary("m");

    const TestStep = B.step("test", "Run library tests");
    TestStep.dependOn(&SlabaTests.step);
    TestStep.dependOn(&SempyTests.step);
    TestStep.dependOn(&ProtexTests.step);
}
