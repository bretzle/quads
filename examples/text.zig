const std = @import("std");
const quads = @import("quads");
const png = @import("png.zig");
const text = quads.experimental.schrift;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const s = 2;

pub fn main() !void {
    const font_data = try std.fs.cwd().readFileAlloc(allocator, "FiraGO-Regular.ttf", 123456789);
    const font = try text.SFT_Font.create(allocator, font_data);

    const sft = text.SFT{
        .font = font,
        .xScale = 16 * s,
        .yScale = 16 * s,
        .flags = text.SFT_DOWNWARD_Y,
    };

    const lmtx = sft.lmetrics();
    std.debug.print("lmtx: {any}\n", .{lmtx});

    const y = 20.0 + lmtx.ascender + lmtx.lineGap;
    _ = y; // autofix

    const view = std.unicode.Utf8View.initComptime("Hello world!");
    var iter = view.iterator();
    while (iter.nextCodepoint()) |codepoint| {
        const gid = sft.lookup(codepoint);

        const mtx = sft.gmetrics(gid);

        var img = text.SFT_Image{
            .width = (mtx.minWidth + 3) & ~@as(i32, 3),
            .height = mtx.minHeight,
            .pixels = undefined,
        };
        img.pixels = try allocator.alloc(u8, @intCast(img.width * img.height));
        defer allocator.free(img.pixels);

        try sft.render(gid, img);

        // std.debug.print("codepoint: {d} ({c}) gid: {d} mtx: {any}\n", .{ codepoint, @as(u8, @truncate(codepoint)), gid, mtx });

        if (mtx.minWidth != 0) {
            const p = png.PNG{
                .width = @intCast(img.width),
                .height = @intCast(img.height),
                .pixels = try allocator.alloc(png.Color, @intCast(img.width * img.height)),
            };

            for (img.pixels, p.pixels) |src, *dst| {
                dst.* = .{ .r = 0x69, .g = 0, .b = 0, .a = src };
            }

            const png_name = try std.fmt.allocPrint(allocator, "chars/{c}.png", .{@as(u8, @truncate(codepoint))});
            const output = try std.fs.cwd().createFile(png_name, .{});
            try p.encode(allocator, output.writer().any());
        }
    }
}
