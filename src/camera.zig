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

fn avErr(ret: c_int) !void {
    if (ret < 0) {
        var buf: [256]u8 = undefined;
        _ = c.av_strerror(ret, &buf, buf.len);
        std.debug.print("FFmpeg error: {s}\n", .{buf[0 .. std.mem.indexOfScalar(u8, &buf, 0) orelse buf.len]});
        return error.FFmpeg;
    }
}

pub const Camera = struct {
    fmt_ctx: ?*c.AVFormatContext = null,
    codec_ctx: ?*c.AVCodecContext = null,
    sws: ?*c.SwsContext = null,
    frame: ?*c.AVFrame = null,
    frame_rgba: ?*c.AVFrame = null,
    pkt: ?*c.AVPacket = null,
    rgba_buf: ?[]u8 = null,
    stream_index: c_int = -1,
    width: c_int = 640,
    height: c_int = 480,

    pub fn init() Camera {
        return .{};
    }

    pub fn open(self: *Camera, want_w: c_int, want_h: c_int, fps: c_int) !void {
        c.avdevice_register_all();
        self.width = want_w;
        self.height = want_h;
        const os = builtin.os.tag;
        var dev_name: [*:0]const u8 = undefined;
        var in_fmt: [*c]const c.AVInputFormat = null;
        if (os == .windows) {
            dev_name = "video=Integrated Camera";
            in_fmt = c.av_find_input_format("dshow");
            if (in_fmt == null) fail("av_find_input_format(dshow) failed");
        } else {
            dev_name = "/dev/video0";
            in_fmt = c.av_find_input_format("v4l2");
            if (in_fmt == null) fail("av_find_input_format(v4l2) failed");
        }

        // Build options: request size/fps; let device choose native pixel format
        var options: ?*c.AVDictionary = null;
        defer c.av_dict_free(&options); // Clean up options dictionary
        {
            if (os == .windows) {
                var sz: [32]u8 = undefined;
                _ = std.fmt.bufPrint(&sz, "{d}x{d}", .{ self.width, self.height }) catch unreachable;
                _ = c.av_dict_set(&options, "video_size", @ptrCast(&sz[0]), 0);

                var fpsbuf: [16]u8 = undefined;
                _ = std.fmt.bufPrint(&fpsbuf, "{d}", .{fps}) catch unreachable;
                _ = c.av_dict_set(&options, "framerate", @ptrCast(&fpsbuf[0]), 0);
            } else {
                // For V4L2, try different option names or let the device choose
                var sz: [32]u8 = undefined;
                _ = std.fmt.bufPrint(&sz, "{d}x{d}", .{ self.width, self.height }) catch unreachable;

                // Try both possible option names
                _ = c.av_dict_set(&options, "s", @ptrCast(&sz[0]), 0);

                var fpsbuf: [16]u8 = undefined;
                _ = std.fmt.bufPrint(&fpsbuf, "{d}", .{fps}) catch unreachable;
                _ = c.av_dict_set(&options, "r", @ptrCast(&fpsbuf[0]), 0);

                // Hints that often help: try mjpeg first for webcams
                _ = c.av_dict_set(&options, "input_format", "mjpeg", 0);
            }
        }

        var fmt_ctx_local: ?*c.AVFormatContext = null;
        try avErr(c.avformat_open_input(@ptrCast(&fmt_ctx_local), dev_name, in_fmt, &options));
        self.fmt_ctx = fmt_ctx_local;

        // Find stream info (optional, but helps some devices)
        _ = c.avformat_find_stream_info(fmt_ctx_local, null);

        // Find best video stream
        var video_stream_idx: c_int = -1;
        {
            var i: c_uint = 0;
            while (i < fmt_ctx_local.?.nb_streams) : (i += 1) {
                const st = fmt_ctx_local.?.streams[i];
                if (st.*.codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
                    video_stream_idx = @as(c_int, @intCast(i));
                    break;
                }
            }
        }
        if (video_stream_idx < 0) fail("no video stream");
        self.stream_index = video_stream_idx;

        // Find decoder & create codec ctx
        const codecpar = fmt_ctx_local.?.streams[@intCast(video_stream_idx)].*.codecpar;
        const dec = c.avcodec_find_decoder(codecpar.*.codec_id);
        if (dec == null) fail("decoder not found");

        const codec_ctx_local = c.avcodec_alloc_context3(dec) orelse fail("alloc codec ctx");
        try avErr(c.avcodec_parameters_to_context(codec_ctx_local, codecpar));

        // Set desired thread count lightly
        codec_ctx_local.*.thread_count = 2;
        try avErr(c.avcodec_open2(codec_ctx_local, dec, null));
        self.codec_ctx = codec_ctx_local;

        // Allocate frames
        self.frame = c.av_frame_alloc() orelse fail("av_frame_alloc");
        self.frame_rgba = c.av_frame_alloc() orelse fail("av_frame_alloc rgba");

        // Set up RGBA target frame buffer
        var rgba_data: [8][*c]u8 = undefined;
        var rgba_linesize: [8]c_int = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
        const num_bytes = c.av_image_get_buffer_size(c.AV_PIX_FMT_RGBA, self.width, self.height, 1);
        if (num_bytes <= 0) fail("av_image_get_buffer_size");

        const buf = std.heap.c_allocator.alloc(u8, @intCast(num_bytes)) catch fail("alloc rgba buf");
        self.rgba_buf = buf;

        try avErr(c.av_image_fill_arrays(
            @ptrCast(&rgba_data),
            @ptrCast(&rgba_linesize),
            buf.ptr,
            c.AV_PIX_FMT_RGBA,
            self.width,
            self.height,
            1,
        ));

        self.frame_rgba.?.*.format = c.AV_PIX_FMT_RGBA;
        self.frame_rgba.?.*.width = self.width;
        self.frame_rgba.?.*.height = self.height;
        self.frame_rgba.?.*.data = rgba_data;
        self.frame_rgba.?.*.linesize = rgba_linesize;

        // Create SWS context (source fmt known only after first decode; we'll init lazily)
        self.sws = null;

        // Packet
        self.pkt = c.av_packet_alloc() orelse fail("av_packet_alloc");
    }

    fn ensureSws(self: *Camera, src_w: c_int, src_h: c_int, src_fmt: c.AVPixelFormat) !void {
        if (self.sws == null) {
            const sws = c.sws_getContext(
                src_w,
                src_h,
                src_fmt,
                self.width,
                self.height,
                c.AV_PIX_FMT_RGBA,
                c.SWS_BILINEAR,
                null,
                null,
                null,
            );
            if (sws == null) fail("sws_getContext");
            self.sws = sws;
        }
    }

    /// Decodes one frame into self.frame_rgba; returns true if a new frame was produced.
    pub fn grab(self: *Camera) !bool {
        const fmt_ctx = self.fmt_ctx orelse return error.NotOpened;
        const codec_ctx = self.codec_ctx orelse return error.NotOpened;
        const frame = self.frame orelse return error.NotOpened;
        const frame_rgba = self.frame_rgba orelse return error.NotOpened;
        const pkt = self.pkt orelse return error.NotOpened;

        // Read packets until we decode a video frame
        while (true) {
            const r = c.av_read_frame(fmt_ctx, pkt);
            if (r == c.AVERROR_EOF) return false;
            if (r < 0) {
                // EAGAIN-like
                return false;
            }
            defer c.av_packet_unref(pkt);

            if (pkt.*.stream_index != self.stream_index) continue;

            try avErr(c.avcodec_send_packet(codec_ctx, pkt));
            while (true) {
                const dr = c.avcodec_receive_frame(codec_ctx, frame);
                if (dr == c.AVERROR_EOF or dr == c.AVERROR(c.EAGAIN)) break;
                try avErr(dr);

                // Lazily create SWS when we know source format/size
                try self.ensureSws(frame.*.width, frame.*.height, @as(c.AVPixelFormat, @intCast(frame.*.format)));

                _ = c.sws_scale(
                    self.sws,
                    &frame.*.data,
                    &frame.*.linesize,
                    0,
                    frame.*.height,
                    &frame_rgba.*.data,
                    &frame_rgba.*.linesize,
                );

                return true;
            }
        }
        // unreachable
    }

    pub fn rgbaSlice(self: *Camera) []u8 {
        const buf = self.rgba_buf orelse return &[_]u8{};
        return buf;
    }

    pub fn deinit(self: *Camera) void {
        if (self.pkt) |p| {
            var pkt_ptr: [*c]c.AVPacket = @ptrCast(p);
            c.av_packet_free(@ptrCast(&pkt_ptr));
        }
        if (self.frame_rgba) |fr| {
            var frame_ptr: [*c]c.AVFrame = @ptrCast(fr);
            c.av_frame_free(@ptrCast(&frame_ptr));
        }
        if (self.frame) |fr| {
            var frame_ptr: [*c]c.AVFrame = @ptrCast(fr);
            c.av_frame_free(@ptrCast(&frame_ptr));
        }
        if (self.codec_ctx) |cc| {
            var ctx_ptr: [*c]c.AVCodecContext = @ptrCast(cc);
            c.avcodec_free_context(@ptrCast(&ctx_ptr));
        }
        if (self.fmt_ctx) |fc| {
            var fmt_ptr: [*c]c.AVFormatContext = @ptrCast(fc);
            c.avformat_close_input(@ptrCast(&fmt_ptr));
        }
        if (self.sws) |s| c.sws_freeContext(s);
        if (self.rgba_buf) |b| std.heap.c_allocator.free(b);
        self.* = .{};
    }
};

