pub const packages = struct {
    pub const @"N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAGwkvwPCiEfKjodWc0roQ1WAK3ZMnZz03gV9vG_C" = struct {
        pub const build_root = "/home/drezdin/.cache/zig/p/N-V-__8AAGwkvwPCiEfKjodWc0roQ1WAK3ZMnZz03gV9vG_C";
        pub const build_zig = @import("N-V-__8AAGwkvwPCiEfKjodWc0roQ1WAK3ZMnZz03gV9vG_C");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAJl1DwBezhYo_VE6f53mPVm00R-Fk28NPW7P14EQ" = struct {
        pub const available = false;
    };
    pub const @"raylib-5.5.0-whq8uLGoOgS_OQP8MRTgFmkCTQAPmAD9fwi5NDW23D5y" = struct {
        pub const build_root = "/home/drezdin/.cache/zig/p/raylib-5.5.0-whq8uLGoOgS_OQP8MRTgFmkCTQAPmAD9fwi5NDW23D5y";
        pub const build_zig = @import("raylib-5.5.0-whq8uLGoOgS_OQP8MRTgFmkCTQAPmAD9fwi5NDW23D5y");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "xcode_frameworks", "N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms" },
            .{ "emsdk", "N-V-__8AAJl1DwBezhYo_VE6f53mPVm00R-Fk28NPW7P14EQ" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "raylib", "N-V-__8AAGwkvwPCiEfKjodWc0roQ1WAK3ZMnZz03gV9vG_C" },
    .{ "raylib_zig", "raylib-5.5.0-whq8uLGoOgS_OQP8MRTgFmkCTQAPmAD9fwi5NDW23D5y" },
};
