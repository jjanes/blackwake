//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
extern "c" fn InitWindow(width: c_int, height: c_int, title: [*:0]const u8) void;
extern "c" fn WindowShouldClose() bool;
extern "c" fn BeginDrawing() void;
extern "c" fn ClearBackground(color: u32) void;
extern "c" fn EndDrawing() void;
extern "c" fn CloseWindow() void;

const Engine = @import("engine.zig").Engine;

pub fn main() !void {
    InitWindow(800, 600, "Raylib in Zig");

    var engine = Engine.init();

    engine.Test();

    while (!WindowShouldClose()) {
        BeginDrawing();
        ClearBackground(0x1E1E1EFF); // RGBA
        EndDrawing();
    }
    CloseWindow();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("blackwake_lib");
