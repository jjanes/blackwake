const c = @cImport({
    @cInclude("raylib.h");
});

pub const Window = struct {
    pub fn init() Window {
        return .{};
    }

    pub fn Create(_: *Window) void {
        c.InitWindow(1200, 1000, "Raylib in Zig");
    }
};
