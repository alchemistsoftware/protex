const std = @import("std");

pub fn build(B: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const Mode = B.standardReleaseOptions();

    const PyPlug = B.addSharedLibrary("pyplug", null, B.version(0, 0, 1));
    PyPlug.addCSourceFiles(&.{"src/pyplug.c",}, &.{"-g",});
    PyPlug.setBuildMode(Mode);
    PyPlug.setOutputDir("./lib");
    PyPlug.addIncludeDir("/usr/include/python3.8");
    PyPlug.linkSystemLibrary("python3.8");
    PyPlug.linkSystemLibrary("crypt");
    PyPlug.linkSystemLibrary("pthread");
    PyPlug.linkSystemLibrary("dl");
    PyPlug.linkSystemLibrary("util");
    PyPlug.linkSystemLibrary("m");
    PyPlug.linkLibC();
    PyPlug.install();

    const Gracie = B.addSharedLibrary("gracie", "src/gracie.zig", B.version(0, 0, 1));
    Gracie.setOutputDir("./lib");
    Gracie.setBuildMode(Mode);
    Gracie.linkLibrary(PyPlug);
    Gracie.addIncludeDir("/usr/include/hs/");
    Gracie.linkSystemLibrary("hs_runtime");
    Gracie.linkLibC();
    Gracie.install();

    const GracieTests = B.addTest("src/gracie.zig");
    GracieTests.setBuildMode(Mode);
    GracieTests.addIncludeDir("/usr/include/hs/");
    GracieTests.linkSystemLibrary("hs_runtime");
    GracieTests.linkLibC();

    const TestStep = B.step("test", "Run library tests");
    TestStep.dependOn(&GracieTests.step);

    // Packager exe
    const Packager = B.addExecutable("packager", "src/packager.zig");
    Packager.setOutputDir("./bin");
    Packager.setBuildMode(Mode);
    Packager.linkSystemLibrary("hs");
    Packager.addIncludeDir("/usr/include/hs/");
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
