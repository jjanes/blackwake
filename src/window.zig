const c = @cImport({
    @cInclude("raylib.h");
});

pub const Window = struct {
    pub fn init() Window {
        return .{};
    }

    pub fn Create(_: *Window) void {
        c.InitWindow(1920, 1080, "Raylib in Zig");
    }
};
