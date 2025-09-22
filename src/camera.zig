const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("raylib.h");

    @cInclude("libavformat/avformat.h");
    @cInclude("libavdevice/avdevice.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libswscale/swscale.h");
    @cInclude("libavutil/imgutils.h");
});

fn fail(msg: []const u8) noreturn {
    std.debug.print("{s}\n", .{msg});
    @panic("fatal");
}

pub const Camera = struct {
    pub fn init() Camera {
        return .{};
    }

    pub fn Open(_: *Camera) !void {
        const os = builtin.os.tag;
        var dev_name: [*:0]const u8 = undefined;
        var in_fmt: *c.AVInputFormat = null;
        if (os == .windows) {
            dev_name = "video=Integrated Camera"; // or your cam's friendly name
            in_fmt = c.av_find_input_format("dshow");
            if (in_fmt == null) fail("av_find_input_format(dshow) failed");
        } else {
            dev_name = "/dev/video0";
            in_fmt = c.av_find_input_format("v4l2");
            if (in_fmt == null) fail("av_find_input_format(v4l2) failed");
        }
    }
};
