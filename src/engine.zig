const std = @import("std");

const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("libavdevice/avdevice.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libswscale/swscale.h");
    @cInclude("libavutil/imgutils.h");
    @cInclude("libavutil/opt.h");
});

const Window = @import("window.zig").Window;
const Camera = @import("camera.zig").Camera(c);
const Desktop = @import("desktop.zig").Desktop(c);

// const vk = @cImport({
//    @cInclude("vulkan/vulkan.h");
//    @cDefine("GRAPHICS_API_VULKAN", "1");
// });

const glfw = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const Engine = struct {
    pub fn init() Engine {
        return .{};
    }

    pub fn Test(_: *Engine) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const alloc = gpa.allocator();

        var camera = Camera.init(alloc);
        var desktop = Desktop.init(alloc);

        defer camera.deinit();
        defer desktop.deinit();

        const cam_width = 640;
        const cam_height = 480;

        const desktop_width = 1920;
        const desktop_height = 1080;

        const fps = 30;

        // Try to open the camera
        std.debug.print("init camera", .{});
        camera.open(cam_width, cam_height, fps, "HD Pro Webcam C920") catch |err| {
            std.debug.print("Failed to open camera: {}\n", .{err});
            return;
        };

        std.debug.print("init desktop", .{});
        desktop.open(desktop_width, desktop_height, fps) catch |err| {
            std.debug.print("Failed to open camera: {}\n", .{err});
            return;
        };

        // var instance: vk.VkInstance = undefined;
        //
        // const app_info = vk.VkApplicationInfo{
        //     .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        //     .pNext = null,
        //     .pApplicationName = "Zig Vulkan",
        //     .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        //     .pEngineName = "No Engine",
        //     .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        //     .apiVersion = vk.VK_API_VERSION_1_0,
        // };
        //
        // const create_info = vk.VkInstanceCreateInfo{
        //     .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        //     .pNext = null,
        //     .flags = 0,
        //     .pApplicationInfo = &app_info,
        //     .enabledExtensionCount = 0,
        //     .ppEnabledExtensionNames = null,
        //     .enabledLayerCount = 0,
        //     .ppEnabledLayerNames = null,
        // };
        //
        // const result = vk.vkCreateInstance(&create_info, null, &instance);
        // if (result != vk.VK_SUCCESS) {
        //     std.debug.print("Failed to create Vulkan instance\n", .{});
        //     return;
        // }
        //
        // std.debug.print("Vulkan instance created!\n", .{});
        //
        // if (glfw.glfwInit() != 1) return error.GlfwInitFailed;
        //
        // defer glfw.glfwTerminate();
        //
        // glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
        // const window = glfw.glfwCreateWindow(800, 600, "Vulkan in Zig", null, null);
        // if (window == null) return error.WindowFailed;
        //
        // while (glfw.glfwWindowShouldClose(window) == 0) {
        //     glfw.glfwPollEvents();
        // }
        //
        // glfw.glfwDestroyWindow(window);
        //
        // const clear_value = vk.VkClearValue{
        //     .color = .{ .float32 = .{ 1.0, 0.0, 0.0, 1.0 } },
        // };
        //
        std.debug.print("TEST", .{});

        var gameWindow = Window.init();

        gameWindow.Create();

        // c.InitWindow(800, 600, "Raylib in Zig");

        // const texture: c.Texture2D = c.LoadTexture("assets/cards/2_of_clubs.png");
        const image = c.LoadImage("assets/cards/2_of_clubs.png");
        const pixels: [*]c.Color = @ptrCast(image.data.?);

        const width = @as(usize, @intCast(image.width));
        const height = @as(usize, @intCast(image.height));
        const pixel_count = width * height;

        for (pixels[0..pixel_count]) |*px| {
            if (px.r == 255 and px.g == 255 and px.b == 255) {
                px.* = c.Color{ .r = 0, .g = 0, .b = 0, .a = 0 }; // Remove white background
            }
        }

        // Load shader
        // const shader = c.LoadShader(null, "shaders/remove_bg.fs");
        //
        // // Set uniforms
        // const key_loc = c.GetShaderLocation(shader, "key_color");
        // const thresh_loc = c.GetShaderLocation(shader, "threshold");
        //
        // var green = c.Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 };
        // c.SetShaderValue(shader, key_loc, &green, c.SHADER_UNIFORM_VEC3);
        //
        // var threshold: f32 = 0.3;
        // c.SetShaderValue(shader, thresh_loc, &threshold, c.SHADER_UNIFORM_FLOAT);

        const texture = c.LoadTextureFromImage(image);
        c.UnloadImage(image);

        var text_camera: c.Texture2D = undefined;
        var has_texture = false;
        // Create initial texture from desktop buffer view
        const desktop_img = desktop.imageView();
        const desktop_tex = c.LoadTextureFromImage(desktop_img);
        var have_desktop_tex = true;

        while (!c.WindowShouldClose()) {
            // 1) Pull a new desktop frame
            if (have_desktop_tex) {
                const dpix = desktop.nextFrame() catch |e| switch (e) {
                    error.EndOfStream => {
                        have_desktop_tex = false;
                        break;
                    },
                    error.NotOpen => {
                        have_desktop_tex = false;
                        break;
                    },
                    else => dpix: {
                        // on transient ffmpeg errors, skip this frame
                        break :dpix null;
                    },
                };

                if (dpix) |frame_pixels| {
                    // Update desktop texture with latest RGBA buffer
                    c.UpdateTexture(desktop_tex, frame_pixels.ptr);
                }
            }

            // 2) Pull a new camera frame
            if (camera.grab() catch false) {
                const pixs = camera.rgbaSlice();
                if (pixs.len > 0) {
                    if (!has_texture) {
                        const img = c.Image{
                            .data = pixs.ptr,
                            .width = 640,
                            .height = 480,
                            .mipmaps = 1,
                            .format = c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
                        };
                        text_camera = c.LoadTextureFromImage(img);
                        has_texture = true;
                    } else {
                        c.UpdateTexture(text_camera, pixs.ptr);
                    }
                }
            }

            // 3) Draw: desktop FIRST (background), camera SECOND (on top)
            c.BeginDrawing();
            c.ClearBackground(c.BLACK);

            if (have_desktop_tex) {
                c.DrawTexture(desktop_tex, 0, 0, c.WHITE);
            }

            if (has_texture) {
                const win_w = c.GetScreenWidth();
                const win_h = c.GetScreenHeight();

                const cam_w: f32 = 320;
                const cam_h: f32 = 240;
                const margin: f32 = 16;

                const x = @as(f32, @floatFromInt(win_w)) - cam_w - margin;
                const y = @as(f32, @floatFromInt(win_h)) - cam_h - margin;

                const src = c.Rectangle{
                    .x = 0,
                    .y = 0,
                    .width = @as(f32, @floatFromInt(text_camera.width)),
                    .height = @as(f32, @floatFromInt(text_camera.height)),
                };
                const dst = c.Rectangle{
                    .x = x,
                    .y = y,
                    .width = cam_w,
                    .height = cam_h,
                };
                const origin = c.Vector2{ .x = 0, .y = 0 };

                c.DrawTexturePro(text_camera, src, dst, origin, 0.0, c.WHITE);
            }

            c.EndDrawing();
        }

        // while (!c.WindowShouldClose()) {
        //     c.BeginDrawing();
        //
        //     if (camera.grab() catch false) {
        //         const pixs = camera.rgbaSlice();
        //         if (pixs.len > 0) {
        //             if (!has_texture) {
        //                 const img = c.Image{ .data = pixs.ptr, .width = 640, .height = 480, .mipmaps = 1, .format = c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 };
        //                 text_camera = c.LoadTextureFromImage(img);
        //                 has_texture = true;
        //             } else {
        //                 // CORE: Update GPU texture with new RAM data
        //                 c.UpdateTexture(text_camera, pixs.ptr);
        //             }
        //         }
        //     }
        //
        //     // c.ClearBackground(c.RAYWHITE);
        //
        //     // c.BeginShaderMode(shader);
        //     c.DrawTexture(texture, 0, 0, c.WHITE);
        //     c.DrawTexture(text_camera, 0, 0, c.WHITE);
        //     // c.EndShaderMode();
        //     //
        //     // // Draw texture inside rectangle
        //     // const destRect = c.Rectangle{ .x = 100, .y = 100, .width = 128, .height = 128 };
        //     // const srcRect = c.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(texture.width), .height = @floatFromInt(texture.height) };
        //     // const origin = c.Vector2{ .x = 0, .y = 0 };
        //     //
        //     // c.DrawTexturePro(texture, srcRect, destRect, origin, 0.0, c.WHITE);
        //     //
        //     // // c.DrawRectangle(100, 100, 200, 150, c.RED);
        //     //
        //     // // c.ClearBackground(0x1E1E1EFF); // RGBA
        //     c.EndDrawing();
        // }
        //
        c.UnloadTexture(texture);
        // c.UnloadShader(shader);
        c.CloseWindow();
    }
};
