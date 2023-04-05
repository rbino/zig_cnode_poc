const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Get otp_dir extracting it from the erlang shell
    const erl_argv = [_][]const u8{
        "erl",
        "-eval",
        "io:format(\"~s\", [code:root_dir()])",
        "-s",
        "init",
        "stop",
        "-noshell",
    };

    // TODO: find a way to extract the version of erl_interface from a command/env
    const erl_interface_version = "erl_interface-5.3";

    const otp_dir = b.exec(&erl_argv);
    defer b.allocator.free(otp_dir);

    const ei_include_dir = std.fs.path.join(b.allocator, &[_][]const u8{
        otp_dir,
        "lib",
        erl_interface_version,
        "include",
    }) catch unreachable;
    defer b.allocator.free(ei_include_dir);

    const ei_lib_dir = std.fs.path.join(b.allocator, &[_][]const u8{
        otp_dir,
        "lib",
        erl_interface_version,
        "lib",
    }) catch unreachable;
    defer b.allocator.free(ei_lib_dir);

    const exe = b.addExecutable(.{
        .name = "zig_cnode_poc",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    exe.install();
    // Include the erl_interface include dir
    exe.addSystemIncludePath(ei_include_dir);
    // Add erl_interface dir to library path
    exe.addLibraryPath(ei_lib_dir);
    // Link to libc since we're calling C code
    exe.linkLibC();
    // Link libei, aka erl_interface
    exe.linkSystemLibrary("ei");


    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = exe.run();

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
