//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

pub fn main() !void {
    var engine = Engine.init();

    engine.Test() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
}

const Engine = @import("engine.zig").Engine;

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("blackwake_lib");
