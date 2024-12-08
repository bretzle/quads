const std = @import("std");
const assert = std.debug.assert;

const Image = @import("../image.zig").Image;

pub const version = "0.10.2";
pub const SFT_DOWNWARD_Y = 0x01;

const POINT_IS_ON_CURVE = 0x01;
const X_CHANGE_IS_SMALL = 0x02;
const Y_CHANGE_IS_SMALL = 0x04;
const REPEAT_FLAG = 0x08;
const X_CHANGE_IS_ZERO = 0x10;
const X_CHANGE_IS_POSITIVE = 0x10;
const Y_CHANGE_IS_ZERO = 0x20;
const Y_CHANGE_IS_POSITIVE = 0x20;

const file_magic_one = 0x00010000;
const file_magic_two = 0x74727565;

pub const SFT_UChar = u21;
pub const SFT_Glyph = u32;

pub const LMetrics = extern struct {
    ascender: f64,
    descender: f64,
    lineGap: f64,
};

pub const GMetrics = extern struct {
    advanceWidth: f64,
    leftSideBearing: f64,
    yOffset: i32 = 0,
    minWidth: u32 = 0,
    minHeight: u32 = 0,
};

pub const Kerning = extern struct {
    xShift: f64,
    yShift: f64,
};

pub const SFT = extern struct {
    const Self = @This();

    font: *SFT_Font,
    xScale: f64,
    yScale: f64,
    xOffset: f64 = 0,
    yOffset: f64 = 0,
    flags: i32,

    pub fn lmetrics(self: *const Self) LMetrics {
        const hhea = gettable(self.font, "hhea") orelse unreachable;
        assert(is_safe_offset(self.font, hhea, 36));

        const factor = self.yScale / @as(f64, @floatFromInt(self.font.unitsPerEm));
        return .{
            .ascender = @as(f64, @floatFromInt(geti16(self.font, hhea + 4))) * factor,
            .descender = @as(f64, @floatFromInt(geti16(self.font, hhea + 6))) * factor,
            .lineGap = @as(f64, @floatFromInt(geti16(self.font, hhea + 8))) * factor,
        };
    }

    pub fn lookup(self: *const Self, codepoint: SFT_UChar) SFT_Glyph {
        return glyph_id(self.font, codepoint);
    }

    pub fn gmetrics(self: *const Self, glyph: SFT_Glyph) GMetrics {
        const xScale = self.xScale / @as(f64, @floatFromInt(self.font.unitsPerEm));

        const adv, const lsb = hor_metrics(self.font, glyph);
        const outline = outline_offset(self.font, glyph);

        var metrics = GMetrics{
            .advanceWidth = @as(f64, @floatFromInt(adv)) * xScale,
            .leftSideBearing = @as(f64, @floatFromInt(lsb)) * xScale + self.xOffset,
        };

        if (outline == 0) {
            return metrics;
        }

        const bbox = glyph_bbox(self, outline);

        metrics.minWidth = @intCast(bbox[2] - bbox[0] + 1);
        metrics.minHeight = @intCast(bbox[3] - bbox[1] + 1);
        metrics.yOffset = if (self.flags & SFT_DOWNWARD_Y != 0) -bbox[3] else bbox[1];

        return metrics;
    }

    pub fn kerning(_: *const Self, leftGlyph: SFT_Glyph, rightGlyph: SFT_Glyph, kerning_: [*c]Kerning) i32 {
        _ = leftGlyph; // autofix
        _ = rightGlyph; // autofix
        _ = kerning_; // autofix
        unreachable;
    }

    pub fn render(self: *const Self, glyph: SFT_Glyph, image: Image(u8)) !void {
        const unitsPerEm: f64 = @floatFromInt(self.font.unitsPerEm);

        const outline = outline_offset(self.font, glyph);
        if (outline == 0) return;
        const bbox = glyph_bbox(self, outline);

        const transform = [6]f64{
            self.xScale / unitsPerEm,
            0.0,
            0.0,
            if (self.flags & SFT_DOWNWARD_Y != 0) -self.yScale / unitsPerEm else self.yScale / unitsPerEm,
            self.xOffset - @as(f64, @floatFromInt(bbox[0])),
            if (self.flags & SFT_DOWNWARD_Y != 0) @as(f64, @floatFromInt(bbox[3])) - self.yOffset else self.yOffset - @as(f64, @floatFromInt(bbox[1])),
        };

        var outl = try Outline.init(self.font.allocator);
        defer outl.deinit();

        try outl.decode_outline(self.font, outline, 0);
        try outl.render_outline(transform, image);
    }
};

pub const SFT_Font = struct {
    const Self = @This();

    data: []const u8,

    source: enum { user, mapping },
    unitsPerEm: u16 = 0,
    locaFormat: i16 = 0,
    numLongHmtx: u16 = 0,

    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, data: []const u8) !*Self {
        assert(data.len <= std.math.maxInt(u32));

        var self = try allocator.create(Self);
        errdefer self.destroy();

        self.* = .{
            .data = data,
            .source = .user,
            .allocator = allocator,
        };

        try self.init();

        return self;
    }

    pub fn destroy(self: *Self) void {
        if (self.source == .mapping) unreachable; // TODO
        self.allocator.destroy(self);
    }

    //////////

    fn init(self: *Self) !void {
        assert(is_safe_offset(self, 0, 12));

        const scalarType = getu32(self, 0);
        assert(scalarType == file_magic_one or scalarType == file_magic_two);

        const head = gettable(self, "head") orelse unreachable;

        assert(is_safe_offset(self, head, 54));
        self.unitsPerEm = getu16(self, head + 18);
        self.locaFormat = @intCast(getu16(self, head + 50));

        const hhea = gettable(self, "hhea") orelse unreachable;
        assert(is_safe_offset(self, hhea, 36));

        self.numLongHmtx = getu16(self, hhea + 34);
    }
};

//#region ttf parsing

fn is_safe_offset(font: *const SFT_Font, offset: u32, margin: u32) bool {
    if (offset > font.data.len) return false;
    if (font.data.len - offset < margin) return false;
    return true;
}

fn getu32(font: *const SFT_Font, offset: u32) u32 {
    assert(offset + 4 <= font.data.len);
    return std.mem.readInt(u32, font.data[offset..][0..4], .big);
}

fn getu16(font: *const SFT_Font, offset: u32) u16 {
    assert(offset + 2 <= font.data.len);
    return std.mem.readInt(u16, font.data[offset..][0..2], .big);
}

fn geti16(font: *const SFT_Font, offset: u32) i16 {
    return @bitCast(getu16(font, offset));
}

fn getu8(font: *const SFT_Font, offset: u32) u8 {
    assert(offset + 1 <= font.data.len);
    return font.data[offset];
}

fn gettable(font: *const SFT_Font, tag: *const [4]u8) ?u32 {
    const num_tables = getu16(font, 4);
    const size = @as(u32, num_tables) * 16;
    assert(is_safe_offset(font, 12, size));

    const elems = std.mem.bytesAsSlice([16]u8, font.data[12..][0..size]);
    assert(elems.len == num_tables);

    const match = std.sort.binarySearch([16]u8, elems, tag, cmpu32) orelse unreachable;
    const idx: u32 = @intCast(match * 16);
    return getu32(font, idx + 12 + 8);
}

fn cmpu32(tag: *const [4]u8, data: [16]u8) std.math.Order {
    return std.math.order(
        std.mem.readInt(u32, tag, .big),
        std.mem.readInt(u32, data[0..4], .big),
    );
}

fn cmpu16(tag: [2]u8, data: [2]u8) std.math.Order {
    return std.math.order(
        std.mem.readInt(u16, &tag, .big),
        std.mem.readInt(u16, &data, .big),
    );
}

//#endregion

fn glyph_id(font: *SFT_Font, charCode: SFT_UChar) SFT_Glyph {
    const cmap = gettable(font, "cmap") orelse unreachable;
    assert(is_safe_offset(font, cmap, 4));

    const numEntries = getu16(font, cmap + 2);

    assert(is_safe_offset(font, cmap, 4 + numEntries * 8));

    // first look for a 'full repertoire'/non-BMP map.
    for (0..numEntries) |i| {
        const idx: u32 = @truncate(i);
        const entry = cmap + 4 + idx * 8;
        const typ = getu16(font, entry) * 0x0100 + getu16(font, entry + 2);

        if (typ == 0x0004 or typ == 0x0312) {
            unreachable;
        }
    }

    // If no 'full repertoire' cmap was found, try looking for a BMP map.
    for (0..numEntries) |i| {
        const idx: u32 = @truncate(i);
        const entry = cmap + 4 + idx * 8;
        const typ = getu16(font, entry) * 0x0100 + getu16(font, entry + 2);
        // Unicode BMP
        if (typ == 0x0003 or typ == 0x0301) {
            const table = cmap + getu32(font, entry + 4);
            assert(is_safe_offset(font, table, 6));

            // Dispatch based on cmap format.
            return switch (getu16(font, table)) {
                4 => CMAP.fmt4(font, table + 6, charCode),
                6 => CMAP.fmt6(font, table + 6, charCode),
                else => unreachable,
            };
        }
    }

    unreachable;
}

const CMAP = struct {
    fn fmt4(font: *SFT_Font, table: u32, charCode: SFT_UChar) SFT_Glyph {
        const key = [2]u8{ @truncate(charCode >> 8), @truncate(charCode) };

        // cmap format 4 only supports the Unicode BMP
        if (charCode > 0xFFFF) {
            return 0;
        }

        const shortCode: u16 = @truncate(charCode);

        assert(is_safe_offset(font, table, 8));
        const segCountX2 = getu16(font, table);
        assert(!(segCountX2 & 1 != 0 or segCountX2 == 0));

        // Find starting positions of the relevant arrays.
        const endCodes = table + 8;
        const startCodes = endCodes + segCountX2 + 2;
        const idDeltas = startCodes + segCountX2;
        const idRangeOffsets = idDeltas + segCountX2;
        assert(is_safe_offset(font, idRangeOffsets, segCountX2));

        // Find the segment that contains shortCode by binary searching over the highest codes in the segments.
        // segPtr = csearch(key, font->memory + endCodes, segCountX2 / 2, 2, cmpu16);
        const elems = std.mem.bytesAsSlice([2]u8, font.data[endCodes..][0..segCountX2]);
        const segPtr = cinarySearch([2]u8, elems, key, cmpu16);
        const segIdxX2: u32 = @intCast(segPtr * 2);

        // Look up segment info from the arrays & short circuit if the spec requires.
        const startCode = getu16(font, startCodes + segIdxX2);
        if (startCode > shortCode)
            unreachable;

        const idDelta = getu16(font, idDeltas + segIdxX2);
        const idRangeOffset = getu16(font, idRangeOffsets + segIdxX2);
        if (idRangeOffset == 0) {
            // Intentional integer under- and overflow.
            return (shortCode + idDelta) & 0xFFFF;
        }

        // Calculate offset into glyph array and determine ultimate value.
        const idOffset = idRangeOffsets + segIdxX2 + idRangeOffset + 2 * @as(u32, shortCode - startCode);
        assert(is_safe_offset(font, idOffset, 2));

        const id = getu16(font, idOffset);
        // Intentional integer under- and overflow.
        return if (id != 0) (id + idDelta) & 0xFFFF else 0;
    }

    fn fmt6(font: *SFT_Font, table: u32, charCode: SFT_UChar) SFT_Glyph {
        _ = font; // autofix
        _ = table; // autofix
        _ = charCode; // autofix
        unreachable;
    }
};

fn cinarySearch(
    comptime T: type,
    items: []const T,
    context: anytype,
    comptime compareFn: fn (@TypeOf(context), T) std.math.Order,
) usize {
    var low: usize = 0;
    var high: usize = items.len;

    while (low < high) {
        // Avoid overflowing in the midpoint calculation
        const mid = low + (high - low) / 2;
        switch (compareFn(context, items[mid])) {
            .eq => return mid,
            .gt => low = mid + 1,
            .lt => high = mid,
        }
    }

    return low;
}

// advanceWidth, leftSideBearing
fn hor_metrics(font: *SFT_Font, glyph: SFT_Glyph) struct { i32, i32 } {
    const hmtx = gettable(font, "hmtx") orelse unreachable;

    if (glyph < font.numLongHmtx) {
        // glyph is inside long metrics segment.
        const offset = hmtx + 4 * glyph;
        assert(is_safe_offset(font, offset, 4));

        const advanceWidth = getu16(font, offset);
        const leftSideBearing = geti16(font, offset + 2);
        return .{ advanceWidth, leftSideBearing };
    } else {
        unreachable;
    }
}

// Returns the offset into the font that the glyph's outline is stored at.
fn outline_offset(font: *SFT_Font, glyph: SFT_Glyph) u32 {
    const loca = gettable(font, "loca") orelse unreachable;
    const glyf = gettable(font, "glyf") orelse unreachable;

    var base: u32 = 0;
    var this: u32 = 0;
    var next: u32 = 0;

    if (font.locaFormat == 0) {
        unreachable;
    } else {
        base = loca + 4 * glyph;
        assert(is_safe_offset(font, base, 8));
        this = getu32(font, base);
        next = getu32(font, base + 4);
    }

    return if (this == next) 0 else glyf + this;
}

fn glyph_bbox(sft: *const SFT, outline: u32) [4]i32 {
    assert(is_safe_offset(sft.font, outline, 10));

    // Read the bounding box from the font file verbatim.
    var box = [4]i32{
        geti16(sft.font, outline + 2),
        geti16(sft.font, outline + 4),
        geti16(sft.font, outline + 6),
        geti16(sft.font, outline + 8),
    };

    std.debug.print("box: {any}", .{box});
    assert(!(box[2] <= box[0] or box[3] <= box[1]));

    // Transform the bounding box into SFT coordinate space.
    const xScale = sft.xScale / @as(f64, @floatFromInt(sft.font.unitsPerEm));
    const yScale = sft.yScale / @as(f64, @floatFromInt(sft.font.unitsPerEm));
    box[0] = @intFromFloat(@floor(@as(f64, @floatFromInt(box[0])) * xScale + sft.xOffset));
    box[1] = @intFromFloat(@floor(@as(f64, @floatFromInt(box[1])) * yScale + sft.yOffset));
    box[2] = @intFromFloat(@ceil(@as(f64, @floatFromInt(box[2])) * xScale + sft.xOffset));
    box[3] = @intFromFloat(@ceil(@as(f64, @floatFromInt(box[3])) * yScale + sft.yOffset));

    return box;
}

const Point = struct {
    x: f64 = 0,
    y: f64 = 0,
};

const Curve = struct {
    beg: u16,
    end: u16,
    ctrl: u16,
};

const Line = struct {
    beg: u16,
    end: u16,
};

const Outline = struct {
    const Self = @This();

    points: std.ArrayList(Point),
    curves: std.ArrayList(Curve),
    lines: std.ArrayList(Line),

    fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .points = try .initCapacity(allocator, 64),
            .curves = try .initCapacity(allocator, 64),
            .lines = try .initCapacity(allocator, 64),
        };
    }

    fn deinit(self: *const Self) void {
        self.points.deinit();
        self.curves.deinit();
        self.lines.deinit();
    }

    fn decode_outline(self: *Self, font: *SFT_Font, offset: u32, recDepth: i32) !void {
        _ = recDepth; // autofix
        assert(is_safe_offset(font, offset, 10));

        const numContours: i32 = geti16(font, offset);

        if (numContours > 0)
            try self.simple_outline(font, offset + 10, @intCast(numContours))
        else if (numContours < 0)
            unreachable;
    }

    fn simple_outline(self: *Self, font: *SFT_Font, offset_: u32, numContours: u32) !void {
        assert(numContours > 0);

        var offset = offset_;
        const basePoint = self.points.items.len;

        assert(is_safe_offset(font, offset, numContours * 2 + 2));

        var numPts = getu16(font, offset + (numContours - 1) * 2);
        assert(numPts < std.math.maxInt(u16));

        numPts += 1;
        assert(self.points.items.len <= std.math.maxInt(u16) - numPts);

        try self.points.ensureTotalCapacity(basePoint + numPts);

        const endPts = try font.allocator.alloc(u16, numContours);
        defer font.allocator.free(endPts);

        const flags = try font.allocator.alloc(u8, numPts);
        defer font.allocator.free(flags);

        for (0..numContours) |i| {
            endPts[i] = getu16(font, offset);
            offset += 2;
        }

        // Ensure that endPts are never falling.
        // Falling endPts have no sensible interpretation and most likely only occur in malicious input.
        // Therefore, we bail, should we ever encounter such input.
        for (0..numContours - 1) |i| {
            assert(endPts[i + 1] >= endPts[i] + 1);
        }

        offset += 2 + getu16(font, offset);

        try simple_flags(font, &offset, numPts, flags);
        try simple_points(font, offset, numPts, flags, &self.points);

        std.debug.print("numPoints = {}\n", .{self.points.items.len});

        var beg: u16 = 0;
        for (0..numContours) |i| {
            const count = endPts[i] - beg + 1;
            try self.decode_contour(flags[beg..], basePoint + beg, count);
            beg = endPts[i] + 1;
        }
    }

    fn decode_contour(self: *Self, flags_: []u8, basePoint_: usize, count_: u16) !void {
        var count = count_;
        var basePoint = basePoint_;
        var flags: [*]u8 = flags_.ptr;

        // Skip contours with less than two points, since the following algorithm can't handle them and
        // they should appear invisible either way (because they don't have any area).
        if (count < 2) return;

        assert(basePoint <= std.math.maxInt(u16) - count);

        var looseEnd: u16 = 0;
        var beg: u16 = 0;
        var ctrl: u16 = 0;
        var center: u16 = 0;
        var cur: u16 = 0;
        var gotCtrl: u32 = 0;

        if (flags[0] & POINT_IS_ON_CURVE != 0) {
            looseEnd = @intCast(basePoint);
            basePoint += 1;
            flags += 1;
            count -= 1;
        } else if (flags[count - 1] & POINT_IS_ON_CURVE != 0) {
            count -= 1;
            looseEnd = @intCast(basePoint + count);
        } else {
            unreachable;
        }

        beg = looseEnd;
        gotCtrl = 0;

        for (0..count) |i| {
            cur = @intCast(basePoint + i);

            if (flags[i] & POINT_IS_ON_CURVE != 0) {
                if (gotCtrl != 0) {
                    self.curves.append(.{ .beg = beg, .end = cur, .ctrl = ctrl }) catch unreachable;
                } else {
                    self.lines.append(Line{ .beg = beg, .end = cur }) catch unreachable;
                }
                beg = cur;
                gotCtrl = 0;
            } else {
                if (gotCtrl != 0) {
                    center = @intCast(self.points.items.len);
                    // assert()
                    self.points.append(midpoint(self.points.items[ctrl], self.points.items[cur])) catch unreachable;

                    // assert()
                    self.curves.append(Curve{ .beg = beg, .end = center, .ctrl = ctrl }) catch unreachable;

                    beg = center;
                }
                ctrl = cur;
                gotCtrl = 1;
            }
        }

        if (gotCtrl != 0) {
            self.curves.append(Curve{ .beg = beg, .end = looseEnd, .ctrl = ctrl }) catch unreachable;
        } else {
            self.lines.append(Line{ .beg = beg, .end = looseEnd }) catch unreachable;
        }
    }

    fn render_outline(self: *Self, transform: [6]f64, image: Image(u8)) !void {
        const numPixels: u32 = @intCast(image.width * image.height);

        const cells = try self.points.allocator.alloc(Cell, numPixels);
        defer self.points.allocator.free(cells);

        @memset(cells, .{ .area = 0, .cover = 0 });

        const buf = Raster{
            .cells = cells,
            .width = @intCast(image.width),
            .height = @intCast(image.height),
        };

        transform_points(self.points.items, transform);
        clip_points(self.points.items, @floatFromInt(image.width), @floatFromInt(image.height));

        try self.tesselate_curves();

        self.draw_lines(buf);
        post_process(buf, image.pixels);
    }

    fn tesselate_curves(self: *Self) !void {
        for (self.curves.items) |curve| {
            try self.tesselate_curve(curve);
        }
    }

    fn tesselate_curve(self: *Self, curve_: Curve) !void {
        var curve = curve_;

        const stack_size = 10;
        var stack: [stack_size]Curve = undefined;
        var top: u32 = 0;

        while (true) {
            if (self.is_flat(curve) or top >= stack_size) {
                self.lines.append(.{ .beg = curve.beg, .end = curve.end }) catch unreachable;
                if (top == 0) break;
                top -%= 1;
                curve = stack[top];
            } else {
                const ctrl0: u16 = @intCast(self.points.items.len);
                self.points.append(midpoint(self.points.items[curve.beg], self.points.items[curve.ctrl])) catch unreachable;

                const ctrl1: u16 = @intCast(self.points.items.len);
                self.points.append(midpoint(self.points.items[curve.ctrl], self.points.items[curve.end])) catch unreachable;

                const pivot: u16 = @intCast(self.points.items.len);
                self.points.append(midpoint(self.points.items[ctrl0], self.points.items[ctrl1])) catch unreachable;

                stack[top] = .{ .beg = curve.beg, .end = pivot, .ctrl = ctrl0 };
                top += 1;
                curve = .{ .beg = pivot, .end = curve.end, .ctrl = ctrl1 };
            }
        }
    }

    // A heuristic to tell whether a given curve can be approximated closely enough by a line.
    fn is_flat(self: *Self, curve: Curve) bool {
        const maxArea2 = 2.0;
        const a = self.points.items[curve.beg];
        const b = self.points.items[curve.ctrl];
        const c = self.points.items[curve.end];
        const g = Point{ .x = b.x - a.x, .y = b.y - a.y };
        const h = Point{ .x = c.x - a.x, .y = c.y - a.y };
        const area2 = @abs(g.x * h.y - h.x * g.y);
        return area2 <= maxArea2;
    }

    fn draw_lines(self: *Self, buf: Raster) void {
        for (self.lines.items) |line| {
            const origin = self.points.items[line.beg];
            const goal = self.points.items[line.end];
            draw_line(buf, origin, goal);
        }
    }
};

// For a 'simple' outline, determines each point of the outline with a set of flags
fn simple_flags(font: *SFT_Font, offset: *u32, numPts: usize, flags: []u8) !void {
    var off = offset.*;

    var value: u8 = 0;
    var repeat: u8 = 0;
    for (0..numPts) |i| {
        if (repeat != 0) {
            repeat -= 1;
        } else {
            assert(is_safe_offset(font, off, 1));
            value = getu8(font, off);
            off += 1;
            if (value & REPEAT_FLAG != 0) {
                assert(is_safe_offset(font, off, 1));
                repeat = getu8(font, off);
                off += 1;
            }
        }
        flags[i] = value;
    }

    offset.* = off;
}

// For a 'simple' outline, decodes both X and Y coordinates for each point of the outline
fn simple_points(font: *SFT_Font, offset_: u32, numPts: usize, flags: []u8, points: *std.ArrayList(Point)) !void {
    var offset = offset_;
    const start = points.items.len;

    {
        var accum: i64 = 0;
        var value: i64 = 0;
        var bit: i64 = 0;
        for (0..numPts) |i| {
            if (flags[i] & X_CHANGE_IS_SMALL != 0) {
                assert(is_safe_offset(font, offset, 1));
                value = getu8(font, offset);
                offset += 1;
                bit = @intFromBool(!!(flags[i] & X_CHANGE_IS_POSITIVE != 0));
                accum -= (value ^ -bit) + bit;
            } else if (flags[i] & X_CHANGE_IS_ZERO == 0) {
                assert(is_safe_offset(font, offset, 2));
                accum += geti16(font, offset);
                offset += 2;
            }

            points.addOneAssumeCapacity().x = @floatFromInt(accum);
        }
    }

    {
        var accum: i64 = 0;
        var value: i64 = 0;
        var bit: i64 = 0;
        for (0..numPts) |i| {
            if (flags[i] & Y_CHANGE_IS_SMALL != 0) {
                assert(is_safe_offset(font, offset, 1));
                value = getu8(font, offset);
                offset += 1;
                bit = @intFromBool(!!(flags[i] & Y_CHANGE_IS_POSITIVE != 0));
                accum -= (value ^ -bit) + bit;
            } else if (flags[i] & Y_CHANGE_IS_ZERO == 0) {
                assert(is_safe_offset(font, offset, 2));
                accum += geti16(font, offset);
                offset += 2;
            }
            points.items[start + i].y = @floatFromInt(accum);
        }
    }
}

fn midpoint(a: Point, b: Point) Point {
    return .{
        .x = 0.5 * (a.x + b.x),
        .y = 0.5 * (a.y + b.y),
    };
}

const Cell = struct {
    area: f64,
    cover: f64,
};

const Raster = struct {
    cells: []Cell,
    width: i32,
    height: i32,
};

fn transform_points(points: []Point, trf: [6]f64) void {
    for (points) |*pt| {
        pt.* = .{
            .x = pt.x * trf[0] + pt.y * trf[2] + trf[4],
            .y = pt.x * trf[1] + pt.y * trf[3] + trf[5],
        };
    }
}

fn clip_points(points: []Point, width: f64, height: f64) void {
    for (points) |*pt| {
        if (pt.x < 0) pt.x = 0;
        if (pt.x >= width) unreachable;
        if (pt.y < 0) pt.y = 0;
        if (pt.y >= height) unreachable;
    }
}

/// Draws a line into the buffer. Uses a custom 2D raycasting algorithm to do so.
fn draw_line(buf: Raster, origin: Point, goal: Point) void {
    const delta = Point{ .x = goal.x - origin.x, .y = goal.y - origin.y };
    const dir = [2]i32{ @intFromFloat(std.math.sign(delta.x)), @intFromFloat(std.math.sign(delta.y)) };

    if (dir[1] == 0) return;

    const crossingIncr = Point{
        .x = if (dir[0] != 0) @abs(1.0 / delta.x) else 1.0,
        .y = @abs(1.0 / delta.y),
    };

    var pixel: [2]i32 = .{ 0, 0 };
    var nextCrossing = Point{};
    var numSteps: u32 = 0;

    if (dir[0] == 0) {
        pixel[0] = @intFromFloat(@floor(origin.x));
        nextCrossing.x = 100.0;
    } else {
        if (dir[0] > 0) {
            pixel[0] = @intFromFloat(@floor(origin.x));
            nextCrossing.x = (origin.x - @as(f64, @floatFromInt(pixel[0]))) * crossingIncr.x;
            nextCrossing.x = crossingIncr.x - nextCrossing.x;
            numSteps += @intFromFloat(@ceil(goal.x) - @floor(origin.x) - 1);
        } else {
            pixel[0] = @intFromFloat(@ceil(origin.x) - 1);
            nextCrossing.x = (origin.x - @as(f64, @floatFromInt(pixel[0]))) * crossingIncr.x;
            numSteps += @intFromFloat(@ceil(origin.x) - @floor(goal.x) - 1);
        }
    }

    if (dir[1] > 0) {
        pixel[1] = @intFromFloat(@floor(origin.y));
        nextCrossing.y = (origin.y - @as(f64, @floatFromInt(pixel[1]))) * crossingIncr.y;
        nextCrossing.y = crossingIncr.y - nextCrossing.y;
        numSteps += @as(u32, @intFromFloat(@ceil(goal.y) - @floor(origin.y))) - 1;
    } else {
        pixel[1] = @intFromFloat(@ceil(origin.y) - 1);
        nextCrossing.y = (origin.y - @as(f64, @floatFromInt(pixel[1]))) * crossingIncr.y;
        numSteps += @intFromFloat(@ceil(origin.y) - @floor(goal.y) - 1);
    }

    var nextDistance = @min(nextCrossing.x, nextCrossing.y);
    const halfDeltaX = 0.5 * delta.x;

    var xAverage: f64 = 0;
    var yDifference: f64 = 0;
    var prevDistance: f64 = 0;

    var cptr: *Cell = undefined;
    var cell: Cell = undefined;

    for (0..numSteps) |_| {
        xAverage = origin.x + (prevDistance + nextDistance) * halfDeltaX;
        yDifference = (nextDistance - prevDistance) * delta.y;
        cptr = &buf.cells[@intCast(pixel[1] * buf.width + pixel[0])];
        cell = cptr.*;
        cell.cover += yDifference;
        xAverage -= @floatFromInt(pixel[0]);
        cell.area += (1.0 - xAverage) * yDifference;
        cptr.* = cell;
        prevDistance = nextDistance;
        const alongX = nextCrossing.x < nextCrossing.y;
        pixel[0] += if (alongX) dir[0] else 0;
        pixel[1] += if (alongX) 0 else dir[1];
        nextCrossing.x += if (alongX) crossingIncr.x else 0.0;
        nextCrossing.y += if (alongX) 0.0 else crossingIncr.y;
        nextDistance = @min(nextCrossing.x, nextCrossing.y);
    }

    xAverage = origin.x + (prevDistance + 1.0) * halfDeltaX;
    yDifference = (1.0 - prevDistance) * delta.y;
    cptr = &buf.cells[@intCast(pixel[1] * buf.width + pixel[0])];
    cell = cptr.*;
    cell.cover += yDifference;
    xAverage -= @floatFromInt(pixel[0]);
    cell.area += (1.0 - xAverage) * yDifference;
    cptr.* = cell;
}

/// Integrate the values in the buffer to arrive at the final grayscale image.
fn post_process(buf: Raster, image: []u8) void {
    var accum: f64 = 0;
    for (0..image.len) |i| {
        const cell = buf.cells[i];
        var value = @abs(accum + cell.area);
        value = @min(value, 1.0);
        value = value * 255.0 + 0.5;
        image[i] = @intFromFloat(value);
        accum += cell.cover;
    }
}
