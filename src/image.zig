const std = @import("std");
const assert = std.debug.assert;

pub const Color = packed struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,
};

pub const Image = struct {
    pixels: []Color,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, width: u32, height: u32) !Image {
        return .{
            .pixels = try allocator.alloc(Color, width * height),
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const Image) void {
        self.allocator.free(self.pixels);
    }
};

pub const png = struct {
    const IHDR = packed struct {
        width: u32,
        height: u32,
        bit_depth: u8,
        color_type: ColorType,
        compression_method: CompressionMethod = .deflate,
        filter_method: FilterMethod = .default,
        interlace_method: InterlaceMethod,

        fn lineBytes(self: *const IHDR) u32 {
            return (self.width * self.bit_depth * self.color_type.components() - 1) / 8 + 1;
        }

        fn decode(chunk: Chunk) !IHDR {
            assert(chunk.chunk_type == .ihdr);

            var stream = std.io.fixedBufferStream(chunk.data);
            const reader = stream.reader();

            const width = try reader.readInt(u32, .big);
            const height = try reader.readInt(u32, .big);
            assert(width != 0 and height != 0);

            const bit_depth = try reader.readInt(u8, .big);
            const color_type = try reader.readEnum(ColorType, .big);
            const compression_method = try reader.readEnum(CompressionMethod, .big);
            const filter_method = try reader.readEnum(FilterMethod, .big);
            const interlace_method = try reader.readEnum(InterlaceMethod, .big);

            return .{
                .width = width,
                .height = height,
                .bit_depth = @truncate(bit_depth),
                .color_type = color_type,
                .compression_method = compression_method,
                .filter_method = filter_method,
                .interlace_method = interlace_method,
            };
        }
    };

    const ColorType = enum(u8) {
        grayscale = 0,
        truecolor = 2,
        indexed = 3,
        gray_alpha = 4,
        truecolor_alpha = 6,

        fn components(self: ColorType) u3 {
            return switch (self) {
                .grayscale => 1,
                .truecolor => 3,
                .indexed => 1,
                .gray_alpha => 2,
                .truecolor_alpha => 4,
            };
        }
    };

    const CompressionMethod = enum(u8) { deflate };

    const FilterMethod = enum(u8) { default };

    const FilterType = enum(u8) { none, sub, up, average, paeth };

    const InterlaceMethod = enum(u8) { none };

    const ChunkType = enum(u32) {
        ihdr = std.mem.bytesToValue(u32, "IHDR"),
        plte = std.mem.bytesToValue(u32, "PLTE"),
        idat = std.mem.bytesToValue(u32, "IDAT"),
        iend = std.mem.bytesToValue(u32, "IEND"),
        trns = std.mem.bytesToValue(u32, "tRNS"),
        bkgd = std.mem.bytesToValue(u32, "bKGD"),
        phys = std.mem.bytesToValue(u32, "pHYs"),
        time = std.mem.bytesToValue(u32, "tIME"),
        _,
    };

    const Chunk = struct {
        chunk_type: ChunkType,
        checksum: u32,
        data: []u8,

        fn read(allocator: std.mem.Allocator, reader: anytype) !Chunk {
            const len = try reader.readInt(u32, .big);
            const chunk_type = try reader.readInt(u32, .little);

            const data = try allocator.alloc(u8, len);
            try reader.readNoEof(data);

            const checksum = try reader.readInt(u32, .big);

            return .{
                .chunk_type = @enumFromInt(chunk_type),
                .checksum = checksum,
                .data = data,
            };
        }

        const ChunkWriter = struct {
            writer: std.io.AnyWriter,
            crc: std.hash.Crc32 = std.hash.Crc32.init(),

            fn writeInt(self: *ChunkWriter, comptime T: type, data: T, endian: std.builtin.Endian) !void {
                var bytes: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;
                std.mem.writeInt(std.math.ByteAlignedInt(@TypeOf(data)), &bytes, data, endian);
                return self.writeAll(&bytes);
            }

            fn writeEnum(self: *ChunkWriter, comptime T: type, data: T, endian: std.builtin.Endian) !void {
                const U = @typeInfo(T).@"enum".tag_type;
                try self.writeInt(U, @intFromEnum(data), endian);
            }

            fn writeAll(self: *ChunkWriter, bytes: []const u8) !void {
                try self.writer.writeAll(bytes);
                self.crc.update(bytes);
            }

            fn finish(self: *ChunkWriter) !void {
                try self.writeInt(u32, self.crc.final(), .big);
            }
        };

        fn write(chunk_type: ChunkType, size: u32, writer: std.io.AnyWriter) !ChunkWriter {
            try writer.writeInt(u32, size, .big);
            try writer.writeInt(u32, @intFromEnum(chunk_type), .little);

            var cw = ChunkWriter{ .writer = writer };
            cw.crc.update(std.mem.asBytes(&chunk_type));
            return cw;
        }
    };

    const magic = "\x89PNG\r\n\x1a\n";

    pub fn decode(allocator: std.mem.Allocator, reader: anytype) !Image {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const alloc = arena.allocator();
        defer arena.deinit();

        if (!try reader.isBytes(magic)) return error.bad_png;

        const ihdr_chunk = try Chunk.read(alloc, reader);
        const ihdr = try IHDR.decode(ihdr_chunk);

        var data = std.ArrayList(u8).init(allocator);
        var pal: ?[]Color = null;
        var trans_color: ?[3]u8 = null;

        while (true) {
            const chunk = try Chunk.read(alloc, reader);

            switch (chunk.chunk_type) {
                .ihdr => return error.bad_png,
                .iend => break,
                .plte => {
                    const rgb = std.mem.bytesAsSlice([3]u8, chunk.data);
                    const palette = try alloc.alloc(Color, rgb.len);
                    for (rgb, 0..) |c, idx| {
                        palette[idx] = .{ .r = c[0], .g = c[1], .b = c[2], .a = 0xFF };
                    }
                    pal = palette;
                },
                .idat => try data.appendSlice(chunk.data),
                .trns => switch (ihdr.color_type) {
                    .gray_alpha, .truecolor_alpha => return error.bad_png,
                    .grayscale => {
                        if (chunk.data.len != 2) return error.bad_png;
                        trans_color = [_]u8{ chunk.data[0], 0, 0 };
                    },
                    .truecolor => {
                        if (chunk.data.len != 6) return error.bad_png;
                        trans_color = [_]u8{ chunk.data[0], chunk.data[2], chunk.data[4] };
                    },
                    .indexed => {
                        for (pal.?[0..chunk.data.len], chunk.data) |*color, alpha| {
                            color.a = alpha;
                        }
                    },
                },
                .bkgd, .phys, .time => {}, // dont need to handle
                else => {
                    const name = @as([4]u8, @bitCast(@intFromEnum(chunk.chunk_type)));
                    if (std.ascii.isUpper(name[0])) std.debug.panic("unsupported chunk: {s}", .{name});
                },
            }
        }

        const pixels = try allocator.alloc(Color, ihdr.width * ihdr.height);
        try readPixels(alloc, ihdr, pal, data.items, pixels);

        return .{
            .width = ihdr.width,
            .height = ihdr.height,
            .pixels = pixels,
        };
    }

    fn readPixels(allocator: std.mem.Allocator, ihdr: IHDR, pal: ?[]Color, data: []const u8, pixels: []Color) !void {
        var compressed_stream = std.io.fixedBufferStream(data);
        var decompressed_stream = std.compress.zlib.decompressor(compressed_stream.reader());
        const reader = decompressed_stream.reader();

        const line_bytes = ihdr.lineBytes();
        var line = try allocator.alloc(u8, line_bytes);
        var prev = try allocator.alloc(u8, line_bytes);

        @memset(line, 0);
        @memset(prev, 0);

        var y: u32 = 0;
        while (y < ihdr.height) : (y += 1) {
            const filter = try reader.readEnum(FilterType, .big);
            try reader.readNoEof(line);

            readScanline(filter, ihdr.bit_depth, ihdr.color_type.components(), prev, line);

            var line_stream = std.io.fixedBufferStream(line);
            var bits = std.io.bitReader(.big, line_stream.reader());

            var x: u32 = 0;
            while (x < ihdr.width) : (x += 1) {
                const pixel: Color = switch (ihdr.color_type) {
                    .grayscale => blk: {
                        const v = try bits.readBitsNoEof(u8, ihdr.bit_depth);
                        break :blk .{ .r = v, .g = v, .b = v, .a = 0xFF };
                    },
                    .gray_alpha => blk: {
                        const v = try bits.readBitsNoEof(u8, ihdr.bit_depth);
                        const a = try bits.readBitsNoEof(u8, ihdr.bit_depth);
                        break :blk .{ .r = v, .g = v, .b = v, .a = a };
                    },
                    .truecolor => .{
                        .r = try bits.readBitsNoEof(u8, ihdr.bit_depth),
                        .g = try bits.readBitsNoEof(u8, ihdr.bit_depth),
                        .b = try bits.readBitsNoEof(u8, ihdr.bit_depth),
                        .a = 0xFF,
                    },
                    .indexed => pal.?[try bits.readBitsNoEof(u8, ihdr.bit_depth)],
                    .truecolor_alpha => .{
                        .r = try bits.readBitsNoEof(u8, ihdr.bit_depth),
                        .g = try bits.readBitsNoEof(u8, ihdr.bit_depth),
                        .b = try bits.readBitsNoEof(u8, ihdr.bit_depth),
                        .a = try bits.readBitsNoEof(u8, ihdr.bit_depth),
                    },
                };

                pixels[y * ihdr.width + x] = pixel;
            }

            std.mem.swap([]u8, &line, &prev);
        }
    }

    fn readScanline(filter: FilterType, bit_depth: u8, components: u4, prev: []u8, line: []u8) void {
        if (filter == .none) return;

        const amt = switch (bit_depth) {
            1, 2, 4 => 1,
            8 => components,
            16 => components * 2,
            else => unreachable,
        };

        for (line, 0..) |*x, idx| {
            const a: u8 = if (idx < amt) 0 else line[idx - amt];
            const b: u8 = prev[idx];
            const c: u8 = if (idx < amt) 0 else prev[idx - amt];

            x.* +%= switch (filter) {
                .none => unreachable,
                .sub => a,
                .up => b,
                .average => @intCast((std.math.add(u9, a, b) catch unreachable) / 2),
                .paeth => paeth(a, b, c),
            };
        }
    }

    fn paeth(a: u8, b: u8, c: u8) u8 {
        const p = @as(i10, a) + b - c;
        const pa = @abs(p - a);
        const pb = @abs(p - b);
        const pc = @abs(p - c);

        return if (pa <= pb and pa <= pc)
            a
        else if (pb <= pc)
            b
        else
            c;
    }

    // Encode logic

    const PlteMap = std.AutoArrayHashMap(Color, void);

    pub fn encode(self: *const Image, allocator: std.mem.Allocator, writer: anytype) !void {
        assert(self.width * self.height == self.pixels.len);
        var arena = std.heap.ArenaAllocator.init(allocator);
        const alloc = arena.allocator();
        defer arena.deinit();

        try writer.writeAll(magic);

        const ihdr = IHDR{
            .width = self.width,
            .height = self.height,
            .bit_depth = 8,
            .color_type = .indexed,
            .interlace_method = .none,
        };

        // write IHDR
        {
            var cw = try Chunk.write(.ihdr, 13, writer);
            try cw.writeInt(u32, ihdr.width, .big);
            try cw.writeInt(u32, ihdr.height, .big);
            try cw.writeInt(u8, ihdr.bit_depth, .big);
            try cw.writeEnum(ColorType, ihdr.color_type, .big);
            try cw.writeEnum(CompressionMethod, ihdr.compression_method, .big);
            try cw.writeEnum(FilterMethod, ihdr.filter_method, .big);
            try cw.writeEnum(InterlaceMethod, ihdr.interlace_method, .big);
            try cw.finish();
        }

        // write PLTE
        var plte: PlteMap = undefined;
        if (ihdr.color_type == .indexed) {
            plte = PlteMap.init(alloc);

            for (self.pixels) |pixel| {
                try plte.put(pixel, {});
            }

            const len: u32 = @truncate(plte.count());
            assert(len >= 1 and len <= 256);

            var cw = try Chunk.write(.plte, len * 3, writer);
            for (plte.keys()) |color| {
                try cw.writeAll(&[3]u8{ color.r, color.g, color.b });
            }
            try cw.finish();
        }

        // write tRNS
        if (ihdr.color_type == .indexed) {
            var alphas = std.ArrayList(u8).init(alloc);

            for (plte.keys()) |color| {
                try alphas.append(color.a);
            }

            const trans = std.mem.trimRight(u8, alphas.items, &.{0xFF});
            if (trans.len != 0) {
                var cw = try Chunk.write(.trns, @truncate(trans.len), writer);
                try cw.writeAll(trans);
                try cw.finish();
            }
        }

        var data = std.ArrayList(u8).init(alloc);
        var compressor = try std.compress.zlib.compressor(data.writer(), .{});
        try writePixels(alloc, ihdr, plte, self.pixels, compressor.writer());
        try compressor.finish();

        // write IDAT
        {
            var cw = try Chunk.write(.idat, @truncate(data.items.len), writer);
            try cw.writeAll(data.items);
            try cw.finish();
        }

        // write IEND
        {
            var cw = try Chunk.write(.iend, 0, writer);
            try cw.finish();
        }
    }

    fn writePixels(allocator: std.mem.Allocator, ihdr: IHDR, plte: PlteMap, pixels: []const Color, writer: anytype) !void {
        const line = try allocator.alloc(u8, ihdr.lineBytes());

        var y: u32 = 0;
        while (y < ihdr.height) : (y += 1) {
            var line_stream = std.io.fixedBufferStream(line);
            var bits = std.io.bitWriter(.big, line_stream.writer());

            var x: u32 = 0;
            while (x < ihdr.width) : (x += 1) {
                const color = pixels[y * ihdr.width + x];

                switch (ihdr.color_type) {
                    .grayscale => try bits.writeBits(color.r, ihdr.bit_depth),
                    .gray_alpha => {
                        try bits.writeBits(color.r, ihdr.bit_depth);
                        try bits.writeBits(color.a, ihdr.bit_depth);
                    },
                    .truecolor => {
                        try bits.writeBits(color.r, ihdr.bit_depth);
                        try bits.writeBits(color.g, ihdr.bit_depth);
                        try bits.writeBits(color.b, ihdr.bit_depth);
                    },
                    .truecolor_alpha => {
                        try bits.writeBits(color.r, ihdr.bit_depth);
                        try bits.writeBits(color.g, ihdr.bit_depth);
                        try bits.writeBits(color.b, ihdr.bit_depth);
                        try bits.writeBits(color.a, ihdr.bit_depth);
                    },
                    .indexed => try bits.writeBits(plte.getIndex(color).?, ihdr.bit_depth),
                }
            }

            // TODO filtering
            try writer.writeByte(@intFromEnum(FilterType.none));
            try writer.writeAll(line);
        }
    }
};
