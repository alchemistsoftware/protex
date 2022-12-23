const std = @import("std");

pub fn build(B: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const Mode = B.standardReleaseOptions();

    const Sempy = B.addSharedLibrary("sempy", null, B.version(0, 0, 1));
    Sempy.addCSourceFiles(&.{"src/sempy.c",}, &.{"-g",});
    Sempy.setBuildMode(Mode);
    Sempy.setOutputDir("./lib");
    Sempy.addIncludePath("/usr/include/python3.8");
    Sempy.linkSystemLibrary("python3.8");
    Sempy.linkSystemLibrary("crypt");
    Sempy.linkSystemLibrary("pthread");
    Sempy.linkSystemLibrary("dl");
    Sempy.linkSystemLibrary("util");
    Sempy.linkSystemLibrary("m");
    Sempy.linkLibC();
    Sempy.install();

    const Gracie = B.addSharedLibrary("gracie", "src/gracie.zig", B.version(0, 0, 1));
    Gracie.setBuildMode(Mode);
    Gracie.setOutputDir("./lib");
    Gracie.addIncludePath("/usr/include/python3.8");
    Gracie.addIncludePath("/usr/include/hs/");
    Gracie.addIncludePath("./src");
    Gracie.linkSystemLibrary("hs_runtime");
    Gracie.linkLibrary(Sempy);
    Gracie.linkLibC();
    Gracie.install();

    const GracieTests = B.addTest("src/gracie.zig");
    GracieTests.setBuildMode(Mode);
    GracieTests.addIncludePath("/usr/include/hs/");
    GracieTests.linkSystemLibrary("hs_runtime");
    GracieTests.linkLibC();

    const SlabaTests = B.addTest("src/slab_allocator.zig");
    SlabaTests.setBuildMode(Mode);

    const TestStep = B.step("test", "Run library tests");
    TestStep.dependOn(&SlabaTests.step);
    TestStep.dependOn(&GracieTests.step);

    // Packager exe
    const Packager = B.addExecutable("packager", "src/packager.zig");
    Packager.setOutputDir("./bin");
    Packager.setBuildMode(Mode);
    Packager.linkSystemLibrary("hs");
    Packager.addIncludePath("/usr/include/hs/");
    Packager.linkLibC();
    Packager.install();

    // C API Check exe
    const CAPICheck = B.addExecutable("capi_check", null);
    CAPICheck.setOutputDir("./bin");
    CAPICheck.setBuildMode(Mode);
    CAPICheck.install();
    CAPICheck.linkLibC();
    CAPICheck.linkLibrary(Gracie);
    CAPICheck.addCSourceFiles(&.{"src/capi_check.c",}, &.{"-g",});
}
