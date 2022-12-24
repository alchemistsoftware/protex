const std = @import("std");

pub fn build(B: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const Mode = B.standardReleaseOptions();

    const Gracie = B.addSharedLibrary("gracie", "src/gracie.zig", B.version(0, 0, 1));
    Gracie.setBuildMode(Mode);
    Gracie.setOutputDir("./lib");
    Gracie.addIncludePath("/usr/include/python3.11");
    Gracie.addIncludePath("/usr/include/hs/");
    Gracie.addIncludePath("./src");
    Gracie.addIncludePath("/usr/include/python3.11");
    Gracie.linkSystemLibrary("python3.11");
    Gracie.linkSystemLibrary("pthread");
    Gracie.linkSystemLibrary("dl");
    Gracie.linkSystemLibrary("util");
    Gracie.linkSystemLibrary("m");
    Gracie.linkSystemLibrary("hs_runtime");
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
