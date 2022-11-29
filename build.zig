const std = @import("std");

pub fn build(B: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const Mode = B.standardReleaseOptions();

    const Lib = B.addSharedLibrary("jpc", "src/jpc.zig", B.version(0, 0, 1));
    Lib.setOutputDir("./lib");
    Lib.setBuildMode(Mode);
    Lib.addIncludeDir("/usr/include/hs/");
    Lib.linkSystemLibrary("hs_runtime"); // TODO(cjb): runtime
    Lib.linkLibC();
    Lib.install();

    const LibTests = B.addTest("src/jpc.zig");
    LibTests.linkSystemLibrary("hs_runtime"); // TODO(cjb): runtime
    LibTests.addIncludeDir("/usr/include/hs/");
    LibTests.linkLibC();
    LibTests.setBuildMode(Mode);

    const TestStep = B.step("test", "Run library tests");
    TestStep.dependOn(&LibTests.step);

    const Packager = B.addExecutable("packager", "src/packager.zig");
    Packager.setOutputDir("./bin");
    Packager.setBuildMode(Mode);
    Packager.linkSystemLibrary("hs");
    Packager.addIncludeDir("/usr/include/hs/");
    Packager.linkLibC();
    Packager.install();
}
