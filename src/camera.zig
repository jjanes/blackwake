const std = @import("std");
const builtin = @import("builtin");

pub fn Camera(comptime C: type) type {
    return struct {
        const c = C;
        const Self = @This();

        allocator: std.mem.Allocator,

        fmt_ctx: ?*c.AVFormatContext = null,
        codec_ctx: ?*c.AVCodecContext = null,
        sws_ctx: ?*c.SwsContext = null,
        video_stream_index: c_int = -1,

        frame: ?*c.AVFrame = null,
        frame_rgba: ?*c.AVFrame = null,

        buffer: ?[*]u8 = null,
        buffer_len: usize = 0,

        width: c_int = 0,
        height: c_int = 0,
        fps: c_int = 0,

        has_new_frame: bool = false,

        // ---------- helpers ----------

        fn getInputFmt() ?*const c.AVInputFormat {
            return switch (builtin.os.tag) {
                .windows => c.av_find_input_format("dshow"),
                .linux => c.av_find_input_format("v4l2"),
                .macos => c.av_find_input_format("avfoundation"),
                else => null,
            };
        }

        fn defaultDeviceName() []const u8 {
            return switch (builtin.os.tag) {
                .windows => "Integrated Camera",
                .linux => "/dev/video0",
                .macos => "0",
                else => "",
            };
        }

        fn buildUrl(buf: []u8, device_name: []const u8) ![:0]u8 {
            const dev = if (device_name.len > 0) device_name else defaultDeviceName();

            return switch (builtin.os.tag) {
                .windows => try std.fmt.bufPrintZ(buf, "video={s}", .{dev}),
                else => try std.fmt.bufPrintZ(buf, "{s}", .{dev}),
            };
        }

        // ---------- API ----------

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Cross-platform camera open.
        pub fn open(
            self: *Self,
            want_w: c_int,
            want_h: c_int,
            want_fps: c_int,
            device_name: []const u8,
        ) !void {
            // if (self.fmt_ctx != null) return error.AlreadyOpen;

            c.avdevice_register_all();

            const input_fmt = getInputFmt() orelse {
                std.debug.print("No supported camera input format for this OS\n", .{});
                return error.UnsupportedOS;
            };

            var options: ?*c.AVDictionary = null;
            defer c.av_dict_free(&options);

            // best-effort size
            var size_buf: [32]u8 = undefined;
            const size_z = try std.fmt.bufPrintZ(&size_buf, "{d}x{d}", .{ want_w, want_h });
            _ = c.av_dict_set(&options, "video_size", size_z, 0);

            // best-effort fps
            var fps_buf: [16]u8 = undefined;
            const fps_z = try std.fmt.bufPrintZ(&fps_buf, "{d}", .{want_fps});
            _ = c.av_dict_set(&options, "framerate", fps_z, 0);

            // build device/url string
            var url_buf: [256]u8 = undefined;
            const url_z = try buildUrl(&url_buf, device_name);

            // open input
            var fmt_ctx_opt: ?*c.AVFormatContext = null;
            if (c.avformat_open_input(&fmt_ctx_opt, url_z, input_fmt, &options) < 0)
                return error.FFmpeg;
            if (fmt_ctx_opt == null)
                return error.FFmpeg;

            if (c.avformat_find_stream_info(fmt_ctx_opt.?, null) < 0) {
                c.avformat_close_input(&fmt_ctx_opt);
                return error.FFmpeg;
            }

            const ctx = fmt_ctx_opt.?;

            // find video stream
            var video_index: c_int = -1;
            const total = @as(usize, @intCast(ctx.nb_streams));

            var i: usize = 0;
            while (i < total) : (i += 1) {
                const st = ctx.streams[i];
                if (st.*.codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
                    video_index = @intCast(i);
                    break;
                }
            }

            if (video_index < 0) {
                c.avformat_close_input(&fmt_ctx_opt);
                return error.NoVideoStream;
            }

            // open decoder
            const codecpar = ctx.streams[@as(usize, @intCast(video_index))].*.codecpar;

            const decoder = c.avcodec_find_decoder(codecpar.*.codec_id) orelse {
                c.avformat_close_input(&fmt_ctx_opt);
                return error.NoDecoder;
            };

            var codec_ctx_opt: ?*c.AVCodecContext = c.avcodec_alloc_context3(decoder);
            if (codec_ctx_opt == null) {
                c.avformat_close_input(&fmt_ctx_opt);
                return error.NoMem;
            }

            if (c.avcodec_parameters_to_context(codec_ctx_opt.?, codecpar) < 0 or
                c.avcodec_open2(codec_ctx_opt.?, decoder, null) < 0)
            {
                c.avcodec_free_context(&codec_ctx_opt);
                c.avformat_close_input(&fmt_ctx_opt);
                return error.FFmpeg;
            }

            const codec_ctx = codec_ctx_opt.?;

            // allocate RGBA buffer
            const buf_size_i = c.av_image_get_buffer_size(
                c.AV_PIX_FMT_RGBA,
                want_w,
                want_h,
                1,
            );
            if (buf_size_i < 0) {
                c.avcodec_free_context(&codec_ctx_opt);
                c.avformat_close_input(&fmt_ctx_opt);
                return error.FFmpeg;
            }
            const buf_size = @as(usize, @intCast(buf_size_i));

            const buf = try self.allocator.alloc(u8, buf_size);

            // allocate frames
            var frame_opt: ?*c.AVFrame = c.av_frame_alloc();
            var frame_rgba_opt: ?*c.AVFrame = c.av_frame_alloc();
            if (frame_opt == null or frame_rgba_opt == null) {
                self.allocator.free(buf);
                if (frame_opt != null) c.av_frame_free(&frame_opt);
                if (frame_rgba_opt != null) c.av_frame_free(&frame_rgba_opt);
                c.avcodec_free_context(&codec_ctx_opt);
                c.avformat_close_input(&fmt_ctx_opt);
                return error.NoMem;
            }

            const frame_rgba_val = frame_rgba_opt.?;
            if (c.av_image_fill_arrays(
                &frame_rgba_val.*.data,
                &frame_rgba_val.*.linesize,
                buf.ptr,
                c.AV_PIX_FMT_RGBA,
                want_w,
                want_h,
                1,
            ) < 0) {
                self.allocator.free(buf);
                c.av_frame_free(&frame_rgba_opt);
                c.av_frame_free(&frame_opt);
                c.avcodec_free_context(&codec_ctx_opt);
                c.avformat_close_input(&fmt_ctx_opt);
                return error.FFmpeg;
            }

            const sws = c.sws_getContext(
                codec_ctx.width,
                codec_ctx.height,
                codec_ctx.pix_fmt,
                want_w,
                want_h,
                c.AV_PIX_FMT_RGBA,
                c.SWS_BILINEAR,
                null,
                null,
                null,
            ) orelse {
                self.allocator.free(buf);
                c.av_frame_free(&frame_rgba_opt);
                c.av_frame_free(&frame_opt);
                c.avcodec_free_context(&codec_ctx_opt);
                c.avformat_close_input(&fmt_ctx_opt);
                return error.FFmpeg;
            };

            // save state
            self.fmt_ctx = fmt_ctx_opt;
            self.codec_ctx = codec_ctx_opt;
            self.sws_ctx = sws;
            self.video_stream_index = video_index;
            self.frame = frame_opt;
            self.frame_rgba = frame_rgba_opt;
            self.buffer = buf.ptr;
            self.buffer_len = buf_size;
            self.width = want_w;
            self.height = want_h;
            self.fps = want_fps;
            self.has_new_frame = false;
        }

        /// Decode next frame into RGBA buffer. Returns true if a new frame was produced.
        pub fn grab(self: *Self) !bool {
            const fmt_ctx = self.fmt_ctx orelse return error.NotOpen;
            const codec_ctx = self.codec_ctx orelse return error.NotOpen;
            const frame = self.frame orelse return error.NotOpen;
            const frame_rgba = self.frame_rgba orelse return error.NotOpen;
            const sws = self.sws_ctx orelse return error.NotOpen;

            var pkt: c.AVPacket = undefined;

            while (true) {
                const ret = c.av_read_frame(fmt_ctx, &pkt);
                if (ret < 0) {
                    self.has_new_frame = false;
                    return false;
                }
                defer c.av_packet_unref(&pkt);

                if (pkt.stream_index != self.video_stream_index)
                    continue;

                if (c.avcodec_send_packet(codec_ctx, &pkt) < 0)
                    continue;

                while (true) {
                    const r = c.avcodec_receive_frame(codec_ctx, frame);
                    if (r == c.AVERROR(c.EAGAIN) or r == c.AVERROR_EOF)
                        break;
                    if (r < 0) {
                        self.has_new_frame = false;
                        return error.FFmpeg;
                    }

                    _ = c.sws_scale(
                        sws,
                        &frame.*.data[0],
                        &frame.*.linesize[0],
                        0,
                        codec_ctx.height,
                        &frame_rgba.*.data[0],
                        &frame_rgba.*.linesize[0],
                    );

                    self.has_new_frame = true;
                    return true;
                }
            }
        }

        /// Slice of latest RGBA frame (only valid if grab() returned true).
        pub fn rgbaSlice(self: *Self) []u8 {
            if (!self.has_new_frame) return &[_]u8{};
            const buf = self.buffer orelse return &[_]u8{};
            return buf[0..self.buffer_len];
        }

        pub fn deinit(self: *Self) void {
            if (self.frame_rgba != null) c.av_frame_free(&self.frame_rgba);
            if (self.frame != null) c.av_frame_free(&self.frame);
            if (self.codec_ctx != null) c.avcodec_free_context(&self.codec_ctx);
            if (self.fmt_ctx != null) c.avformat_close_input(&self.fmt_ctx);
            if (self.sws_ctx) |s| c.sws_freeContext(s);
            if (self.buffer) |ptr| self.allocator.free(ptr[0..self.buffer_len]);

            self.video_stream_index = -1;
            self.buffer = null;
            self.buffer_len = 0;
            self.width = 0;
            self.height = 0;
            self.fps = 0;
            self.has_new_frame = false;
        }
    };
}
