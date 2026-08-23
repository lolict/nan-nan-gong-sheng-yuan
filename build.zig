// build.zig — 南囡囝共生元 构建脚本
// ============================================
// 用法:
//   zig build-exe nan.c            # 直接编译 C 解释器
//   zig build                      # 用本脚本构建
//
// 不依赖 gcc，Zig 自带 C 编译器后端（clang/LLVM）
// ============================================

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. 编译 nan.c → nan 解释器（零外部依赖，只用 libc）
    const nan_exe = b.addExecutable(.{
        .name = "nan",
        .target = target,
        .optimize = optimize,
    });
    nan_exe.addCSourceFile(.{
        .file = .{ .path = "nan.c" },
        .flags = &.{"-std=c99"},
    });
    nan_exe.linkLibC();
    nan_exe.linkSystemLibrary("m");
    b.installArtifact(nan_exe);

    // 2. 运行命令: zig build run -- boot.nan
    const run_cmd = b.addRunArtifact(nan_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "运行 nan 解释器");
    run_step.dependOn(&run_cmd.step);
}
