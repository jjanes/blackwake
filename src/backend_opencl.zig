pub fn init() void { /* raylib InitWindow, etc */ }
pub fn processFrame(buf: []u8, w: usize, h: usize) void {
    // Example: invert red channel
    for (buf) |*b| {
        b.* = 255 - b.*;
    }
}

