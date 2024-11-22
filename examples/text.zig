const std = @import("std");
const quads = @import("quads");
const gfx = quads.gfx;
const image = quads.image;
const text = quads.experimental.schrift;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const s = 2;

pub fn main() !void {
    try quads.init(allocator, .{});

    var window = try quads.createWindow(.{});
    defer window.destroy();

    try window.createContext(.{});
    window.makeContextCurrent();

    try gfx.init(allocator, .{ .loader = quads.glGetProcAddress });
    defer gfx.deinit();

    const font_data = try std.fs.cwd().readFileAlloc(allocator, "FiraGO-Regular.ttf", 123456789);
    const font = try Font.load(allocator, font_data);
    _ = font; // autofix

    // const lmtx = sft.lmetrics();
    // std.debug.print("lmtx: {any}\n", .{lmtx});

    // const y = 20.0 + lmtx.ascender + lmtx.lineGap;
    // _ = y; // autofix

    // const view = std.unicode.Utf8View.initComptime("Hello world!");
    // var iter = view.iterator();
    // while (iter.nextCodepoint()) |codepoint| {
    //     const gid = sft.lookup(codepoint);

    //     const mtx = sft.gmetrics(gid);

    //     var img = text.SFT_Image{
    //         .width = (mtx.minWidth + 3) & ~@as(i32, 3),
    //         .height = mtx.minHeight,
    //         .pixels = undefined,
    //     };
    //     img.pixels = try allocator.alloc(u8, @intCast(img.width * img.height));
    //     defer allocator.free(img.pixels);

    //     try sft.render(gid, img);

    //     // std.debug.print("codepoint: {d} ({c}) gid: {d} mtx: {any}\n", .{ codepoint, @as(u8, @truncate(codepoint)), gid, mtx });

    //     if (mtx.minWidth != 0) {
    //         const p = try image.Image.create(allocator, @intCast(img.width), @intCast(img.height));
    //         defer p.deinit();

    //         for (img.pixels, p.pixels) |src, *dst| {
    //             dst.* = .{ .r = 0x69, .g = 0, .b = 0, .a = src };
    //         }

    //         const png_name = try std.fmt.allocPrint(allocator, "chars/{c}.png", .{@as(u8, @truncate(codepoint))});
    //         const output = try std.fs.cwd().createFile(png_name, .{});
    //         try image.png.encode(&p, allocator, output.writer().any());
    //     }
    // }
}

const Font = struct {
    sft: text.SFT,
    atlas: Atlas,
    chars: std.AutoHashMap(u21, text.GMetrics),

    pub fn load(alloc: std.mem.Allocator, ttf_data: []const u8) !Font {
        const sft = text.SFT{
            .font = try text.SFT_Font.create(allocator, ttf_data),
            .xScale = 16 * s,
            .yScale = 16 * s,
            .flags = text.SFT_DOWNWARD_Y,
        };

        var atlas = try Atlas.create(alloc);
        var chars = std.AutoHashMap(u21, text.GMetrics).init(alloc);

        for (0..256) |c| {
            const codepoint: u8 = @truncate(c);
            if (!std.ascii.isAlphanumeric(codepoint)) continue;
            std.debug.print("codepoint: {c}\n", .{codepoint});
            const gid = sft.lookup(codepoint);

            const mtx = sft.gmetrics(gid);

            var img = try image.Image(u8).create(allocator, (mtx.minWidth + 3) & ~@as(u32, 3), mtx.minHeight);
            defer img.deinit();

            try sft.render(gid, img);

            try atlas.cacheImage(codepoint, img);
            try chars.put(codepoint, mtx);
        }

        return .{
            .sft = sft,
            .atlas = atlas,
            .chars = chars,
        };
    }
};

const Atlas = struct {
    texture: gfx.TextureId,
    img: image.Image(u8),
    cursor_x: u32 = 0,
    cursor_y: u32 = 0,

    max_line_height: u32 = 0,
    dirty: bool = false,

    const gap = 2;

    fn create(alloc: std.mem.Allocator) !Atlas {
        const img = try image.Image(u8).create(alloc, 512, 512);
        const texture = gfx.createTexture(.{
            .width = img.width,
            .height = img.height,
            .access = .render_target,
        });

        return .{ .texture = texture, .img = img };
    }

    fn cacheImage(self: *Atlas, key: u21, raster: image.Image(u8)) !void {
        _ = self; // autofix
        _ = key; // autofix
        _ = raster; // autofix
        // _ = key; // autofix
        // const width: u32 = @intCast(raster.width);
        // const height: u32 = @intCast(raster.height);

        // const x = if (self.cursor_x + width < self.img.width) blk: {
        //     if (height > self.max_line_height) {
        //         self.max_line_height = height;
        //     }

        //     const res = self.cursor_x + gap;
        //     self.cursor_x += width + gap * 2;
        //     break :blk res;
        // } else unreachable;
        // const y = self.cursor_y;

        // if (y + height > self.img.height or x + width > self.img.width) {
        //     // resize atlas
        //     unreachable;
        // } else {
        //     self.dirty = true;

        //     for (0..height) |j| for (0..width) |i| {
        //         self.img.set(x + i,  y + j, raster[])
        //     }
        // }
    }
};
