const std = @import("std");

pub fn build(B: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const Mode = B.standardReleaseOptions();

    const Gracie = B.addSharedLibrary("gracie", "src/gracie.zig", B.version(0, 0, 4));
    Gracie.setBuildMode(Mode);
    Gracie.setOutputDir("./lib");
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
    GracieTests.setOutputDir("./bin");
    GracieTests.addIncludePath("/usr/include/hs/");
    GracieTests.addIncludePath("./src");
    GracieTests.addIncludePath("/usr/include/python3.11");
    GracieTests.linkSystemLibrary("python3.11");
    GracieTests.linkSystemLibrary("pthread");
    GracieTests.linkSystemLibrary("dl");
    GracieTests.linkSystemLibrary("util");
    GracieTests.linkSystemLibrary("m");
    GracieTests.linkSystemLibrary("hs_runtime");
    GracieTests.linkLibC();

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
    TestStep.dependOn(&GracieTests.step);

    // Packager exe
    const Packager = B.addExecutable("packager", "src/packager.zig");
    Packager.setOutputDir("./bin");
    Packager.setBuildMode(Mode);
    Packager.linkSystemLibrary("hs");
    Packager.addIncludePath("/usr/include/hs/");
    Packager.linkLibC();
    Packager.install();

    // Webserver
    const Server = B.addExecutable("webserv", "src/webserv.zig");
    Server.setOutputDir("./bin");
    Server.setBuildMode(Mode);
    Server.linkSystemLibrary("hs");
    Server.addIncludePath("/usr/include/hs/");
    Server.linkLibC();
    Server.install();

    // C API Check exe
    const CAPICheck = B.addExecutable("capi_check", null);
    CAPICheck.setOutputDir("./bin");
    CAPICheck.setBuildMode(Mode);
    CAPICheck.install();
    CAPICheck.linkLibC();
    CAPICheck.linkLibrary(Gracie);
    CAPICheck.addCSourceFiles(&.{"src/capi_check.c",}, &.{"-g",});
}
