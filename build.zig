const std = @import("std");

pub fn build(B: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const Mode = B.standardReleaseOptions();

    const Protex = B.addSharedLibrary("protex", "src/protex.zig", B.version(0, 5, 0));
    Protex.setBuildMode(Mode);
    Protex.setOutputDir("./lib");
    Protex.addIncludePath("/usr/include/hs/");
    Protex.addIncludePath("./src");
    Protex.addIncludePath("/usr/include/python3.11");
    Protex.linkSystemLibrary("python3.11");
    Protex.linkSystemLibrary("pthread");
    Protex.linkSystemLibrary("dl");
    Protex.linkSystemLibrary("util");
    Protex.linkSystemLibrary("m");
    Protex.linkSystemLibrary("hs_runtime");
    Protex.linkLibC();
    Protex.install();

    const ProtexTests = B.addTest("src/protex.zig");
    ProtexTests.setBuildMode(Mode);
    ProtexTests.setOutputDir("./bin");
    ProtexTests.addIncludePath("/usr/include/hs/");
    ProtexTests.addIncludePath("./src");
    ProtexTests.addIncludePath("/usr/include/python3.11");
    ProtexTests.linkSystemLibrary("python3.11");
    ProtexTests.linkSystemLibrary("pthread");
    ProtexTests.linkSystemLibrary("dl");
    ProtexTests.linkSystemLibrary("util");
    ProtexTests.linkSystemLibrary("m");
    ProtexTests.linkSystemLibrary("hs_runtime");
    ProtexTests.linkLibC();

    const SlabaTests = B.addTest("src/slab_allocator.zig");
    SlabaTests.setBuildMode(Mode);

    const SempyTests = B.addTest("src/sempy.zig");
    SempyTests.setBuildMode(Mode);
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

    // Packager exe

    const Packager = B.addExecutable("packager", "src/packager.zig");
    Packager.setOutputDir("./bin");
    Packager.setBuildMode(Mode);
    Packager.linkSystemLibrary("hs");
    Packager.addIncludePath("/usr/include/hs/");
    Packager.linkLibC();
    Packager.install();

    // C API Check exe

    const CAPICheck = B.addExecutable("capi_io", null);
    CAPICheck.setOutputDir("./bin");
    CAPICheck.setBuildMode(Mode);
    CAPICheck.install();
    CAPICheck.linkLibC();
    CAPICheck.linkLibrary(Protex);
    CAPICheck.addCSourceFiles(&.{"src/capi_io.c",}, &.{"-g",});
}
