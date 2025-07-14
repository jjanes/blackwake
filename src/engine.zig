const std = @import("std");

pub const Engine = struct {
    pub fn init() Engine {
        return .{};
    }

    pub fn Test(_: *Engine) void {
        std.debug.print("TEST", .{});
    }
};
