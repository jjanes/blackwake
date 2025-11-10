const std = @import("std");

pub fn Desktop(comptime C: type) type {
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

        buffer: ?[*]u8 = null, // RGBA pixels
        buffer_len: usize = 0,

        width: c_int = 0,
        height: c_int = 0,
        fps: c_int = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Open desktop capture (gdigrab) and prepare RGBA buffer for raylib.
        pub fn open(self: *Self, want_w: c_int, want_h: c_int, want_fps: c_int) !void {
            if (self.fmt_ctx != null) return error.AlreadyOpen;

            c.avdevice_register_all();

            const input_fmt = c.av_find_input_format("gdigrab") orelse {
                std.debug.print("gdigrab not found\n", .{});
                return error.NoGdiGrab;
            };

            var options: ?*c.AVDictionary = null;
            defer c.av_dict_free(&options);

            // video_size=WIDTHxHEIGHT
            var size_buf: [32]u8 = undefined;
            const size_z = try std.fmt.bufPrintZ(&size_buf, "{d}x{d}", .{ want_w, want_h });
            if (c.av_dict_set(&options, "video_size", size_z, 0) < 0)
                return error.FFmpeg;

            // framerate=FPS
            var fps_buf: [16]u8 = undefined;
            const fps_z = try std.fmt.bufPrintZ(&fps_buf, "{d}", .{want_fps});
            if (c.av_dict_set(&options, "framerate", fps_z, 0) < 0)
                return error.FFmpeg;

            // capture cursor (optional)
            _ = c.av_dict_set(&options, "draw_mouse", "1", 0);

            const url: [:0]const u8 = "desktop";

            // ---- Open input ----
            var fmt_ctx_opt: ?*c.AVFormatContext = null;
            if (c.avformat_open_input(&fmt_ctx_opt, url, input_fmt, &options) < 0)
                return error.FFmpeg;
            if (fmt_ctx_opt == null)
                return error.FFmpeg;

            if (c.avformat_find_stream_info(fmt_ctx_opt.?, null) < 0) {
                c.avformat_close_input(&fmt_ctx_opt);
                return error.FFmpeg;
            }

            const ctx = fmt_ctx_opt.?;

            // ---- Find video stream ----
            var video_index: c_int = -1;
            const total_streams = @as(usize, @intCast(ctx.nb_streams));

            var i: usize = 0;
            while (i < total_streams) : (i += 1) {
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

            // ---- Open decoder ----
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

            // ---- Allocate RGBA buffer ----
            const out_w = want_w;
            const out_h = want_h;

            const buf_size_i = c.av_image_get_buffer_size(
                c.AV_PIX_FMT_RGBA,
                out_w,
                out_h,
                1,
            );
            if (buf_size_i < 0) {
                c.avcodec_free_context(&codec_ctx_opt);
                c.avformat_close_input(&fmt_ctx_opt);
                return error.FFmpeg;
            }
            const buf_size = @as(usize, @intCast(buf_size_i));

            const buf = try self.allocator.alloc(u8, buf_size);

            // ---- Allocate frames ----
            var frame_opt: ?*c.AVFrame = c.av_frame_alloc();
            if (frame_opt == null) {
                self.allocator.free(buf);
                c.avcodec_free_context(&codec_ctx_opt);
                c.avformat_close_input(&fmt_ctx_opt);
                return error.NoMem;
            }

            var frame_rgba_opt: ?*c.AVFrame = c.av_frame_alloc();
            if (frame_rgba_opt == null) {
                self.allocator.free(buf);
                c.av_frame_free(&frame_opt);
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
                out_w,
                out_h,
                1,
            ) < 0) {
                self.allocator.free(buf);
                c.av_frame_free(&frame_rgba_opt);
                c.av_frame_free(&frame_opt);
                c.avcodec_free_context(&codec_ctx_opt);
                c.avformat_close_input(&fmt_ctx_opt);
                return error.FFmpeg;
            }

            // ---- swscale context ----
            const sws = c.sws_getContext(
                codec_ctx.width,
                codec_ctx.height,
                codec_ctx.pix_fmt,
                out_w,
                out_h,
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

            // ---- Save state into self ----
            self.fmt_ctx = fmt_ctx_opt;
            self.codec_ctx = codec_ctx_opt;
            self.sws_ctx = sws;
            self.video_stream_index = video_index;

            self.frame = frame_opt;
            self.frame_rgba = frame_rgba_opt;

            self.buffer = buf.ptr;
            self.buffer_len = buf_size;

            self.width = out_w;
            self.height = out_h;
            self.fps = want_fps;
        }

        /// Decode next frame into our RGBA buffer.
        /// Returns slice usable with raylib UpdateTexture.
        pub fn nextFrame(self: *Self) ![]u8 {
            const fmt_ctx = self.fmt_ctx orelse return error.NotOpen;
            const codec_ctx = self.codec_ctx orelse return error.NotOpen;
            const frame = self.frame orelse return error.NotOpen;
            const frame_rgba = self.frame_rgba orelse return error.NotOpen;
            const sws = self.sws_ctx orelse return error.NotOpen;
            const buf_ptr = self.buffer orelse return error.NotOpen;

            var pkt: c.AVPacket = undefined;

            while (true) {
                const ret = c.av_read_frame(fmt_ctx, &pkt);
                if (ret < 0) return error.EndOfStream;
                defer c.av_packet_unref(&pkt);

                if (pkt.stream_index != self.video_stream_index)
                    continue;

                if (c.avcodec_send_packet(codec_ctx, &pkt) < 0)
                    continue;

                while (true) {
                    const r = c.avcodec_receive_frame(codec_ctx, frame);
                    if (r == c.AVERROR(c.EAGAIN) or r == c.AVERROR_EOF)
                        break;
                    if (r < 0) return error.FFmpeg;

                    _ = c.sws_scale(
                        sws,
                        &frame.*.data[0],
                        &frame.*.linesize[0],
                        0,
                        codec_ctx.height,
                        &frame_rgba.*.data[0],
                        &frame_rgba.*.linesize[0],
                    );

                    return buf_ptr[0..self.buffer_len];
                }
            }
        }

        /// Build a raylib Image view over our RGBA buffer.
        /// Use this once with LoadTextureFromImage, then UpdateTexture each frame.
        pub fn imageView(self: *Self) c.Image {
            const buf_ptr = self.buffer orelse return c.Image{
                .data = null,
                .width = 0,
                .height = 0,
                .mipmaps = 1,
                .format = c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
            };

            return c.Image{
                .data = buf_ptr,
                .width = self.width,
                .height = self.height,
                .mipmaps = 1,
                .format = c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.frame_rgba != null) {
                c.av_frame_free(&self.frame_rgba);
            }
            if (self.frame != null) {
                c.av_frame_free(&self.frame);
            }
            if (self.codec_ctx != null) {
                c.avcodec_free_context(&self.codec_ctx);
            }
            if (self.fmt_ctx != null) {
                c.avformat_close_input(&self.fmt_ctx);
            }
            if (self.sws_ctx) |s| {
                c.sws_freeContext(s);
                self.sws_ctx = null;
            }
            if (self.buffer) |ptr| {
                self.allocator.free(ptr[0..self.buffer_len]);
                self.buffer = null;
                self.buffer_len = 0;
            }

            self.video_stream_index = -1;
            self.width = 0;
            self.height = 0;
            self.fps = 0;
        }
    };
}
