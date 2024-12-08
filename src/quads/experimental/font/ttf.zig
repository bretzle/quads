const std = @import("std");
const builtin = @import("builtin");
const testing = @import("../../testing.zig");

const assert = std.debug.assert;

const Fixed = packed struct(u32) {
    frac: i16,
    integer: i16,
};

pub const TTF = struct {
    const Self = @This();

    const OffsetTable = packed struct {
        scalar: u32,
        num_tables: u16,
        search_range: u16,
        entry_selector: u16,
        range_shift: u16,
    };

    const TableEntry = extern struct {
        tag: [4]u8,
        checksum: u32,
        offset: u32,
        length: u32,

        fn get(self: *const TableEntry, bytes: []const u8) []const u8 {
            return bytes[self.offset..][0..self.length];
        }
    };

    const Tag = enum {
        // required tables
        cmap,
        glyf,
        head,
        // hhea,
        // hmtx,
        loca,
        // maxp,
        // name,
        // post,

        // optional tables
        // TODO
    };

    const HeadTable = packed struct {
        version: Fixed,
        font_revision: Fixed,
        check_sum_adjustment: u32,
        magic_number: u32,
        flags: u16,
        units_per_em: u16,
        created: i64,
        modified: i64,
        x_min: i16,
        y_min: i16,
        x_max: i16,
        y_max: i16,
        mac_style: u16,
        lowest_rec_ppem: u16,
        font_direction_hint: i16,
        index_to_loc_format: i16,
        glyph_data_format: i16,
    };

    const CmapTable = struct {
        bytes: []const u8,

        const Index = packed struct {
            version: u16,
            num_subtables: u16,
        };

        const Subtable = packed struct {
            platform_id: u16,
            platform_specific_id: u16,
            offset: u32,

            fn isUnicode(self: *const Subtable) bool {
                if (self.platform_id == 0 and self.platform_specific_id == 3) return true;
                if (self.platform_id == 3 and self.platform_specific_id == 1) return true;
                return false;
            }
        };

        const Format4 = struct {
            format: u16,
            length: u16,
            language: u16,
            seg_count_x2: u16,
            search_range: u16,
            entry_selector: u16,
            range_shift: u16,
            end_code: []const u16,
            reserved_pad: u16,
            start_code: []const u16,
            id_delta: []const u16,
            id_range_offset: []const u16,
            glyph_indices: []const u16,

            fn deinit(self: *const Format4, allocator: std.mem.Allocator) void {
                allocator.free(self.end_code);
                allocator.free(self.start_code);
                allocator.free(self.id_delta);
                allocator.free(self.id_range_offset);
                allocator.free(self.glyph_indices);
            }

            fn getGlyphIndex(self: *const Format4, c: u16) u16 {
                var i: usize = 0;
                while (i < self.end_code.len) {
                    if (self.end_code[i] > c) break;
                    i += 1;
                }

                if (i >= self.end_code.len) unreachable;
                // [ id range ] [glyph indices ]
                //     |--------------|
                //     i   offs_bytes
                const byte_offset_from_id_offset = self.id_range_offset[i];
                if (byte_offset_from_id_offset == 0) {
                    return self.id_delta[i] +% c;
                } else {
                    const offs_from_loc = byte_offset_from_id_offset / 2 + (c - self.start_code[i]);
                    const dist_to_end = self.id_range_offset.len - i;
                    const glyph_index_index = offs_from_loc - dist_to_end;
                    return self.glyph_indices[glyph_index_index] +% self.id_delta[i];
                }
            }
        };

        fn readIndex(self: CmapTable) Index {
            comptime assert(@sizeOf(Index) == @bitSizeOf(Index) / 8);
            return help.parse(Index, self.bytes[0..@sizeOf(Index)]);
        }

        fn readSubtable(self: CmapTable, idx: usize) Subtable {
            comptime assert(@sizeOf(Subtable) == @bitSizeOf(Subtable) / 8);
            const start = @sizeOf(Index) + idx * @sizeOf(Subtable);
            const end = start + @sizeOf(Subtable);
            return help.parse(Subtable, self.bytes[start..end]);
        }

        fn subTableFormat(self: CmapTable, offset: u32) u16 {
            return help.parse(u16, self.bytes[offset .. offset + 2]);
        }

        fn readFormat4(self: CmapTable, allocator: std.mem.Allocator, offset: usize) !Format4 {
            var stream = help.Stream{ .data = self.bytes[offset..] };

            const format = stream.readVal(u16);
            const length = stream.readVal(u16);
            const language = stream.readVal(u16);
            const seg_count_x2 = stream.readVal(u16);
            const search_range = stream.readVal(u16);
            const entry_selector = stream.readVal(u16);
            const range_shift = stream.readVal(u16);
            const end_code: []const u16 = try stream.readArray(u16, allocator, seg_count_x2 / 2);
            const reserved_pad = stream.readVal(u16);
            const start_code: []const u16 = try stream.readArray(u16, allocator, seg_count_x2 / 2);
            const id_delta: []const u16 = try stream.readArray(u16, allocator, seg_count_x2 / 2);
            const id_range_offset: []const u16 = try stream.readArray(u16, allocator, seg_count_x2 / 2);
            const glyph_indices: []const u16 = try stream.readArray(u16, allocator, (stream.data.len - stream.idx) / 2);

            return .{
                .format = format,
                .length = length,
                .language = language,
                .seg_count_x2 = seg_count_x2,
                .search_range = search_range,
                .entry_selector = entry_selector,
                .range_shift = range_shift,
                .end_code = end_code,
                .reserved_pad = reserved_pad,
                .start_code = start_code,
                .id_delta = id_delta,
                .id_range_offset = id_range_offset,
                .glyph_indices = glyph_indices,
            };
        }
    };

    const GlyfTable = struct {
        bytes: []const u8,

        const Common = packed struct {
            number_of_contours: i16,
            x_min: i16,
            y_min: i16,
            x_max: i16,
            y_max: i16,
        };

        const SimpleGlyphFlag = packed struct(u8) {
            on_curve_point: bool,
            x_short_vector: bool,
            y_short_vector: bool,
            repeat_flag: bool,
            x_is_same_or_positive_x_short_vector: bool,
            y_is_same_or_positive_y_short_vector: bool,
            overlap_simple: bool,
            reserved: bool,
        };

        const GlyphParseVariant = enum {
            short_pos,
            short_neg,
            long,
            repeat,

            fn fromBools(short: bool, is_same_or_positive_short: bool) GlyphParseVariant {
                return if (short)
                    if (is_same_or_positive_short)
                        .short_pos
                    else
                        .short_neg
                else 
                    if (is_same_or_positive_short)
                        .repeat
                    else
                        .long;
            }
        };

        const SimpleGlyph = struct {
            common: Common,
            end_pts_of_contours: []u16,
            instruction_length: u16,
            instructions: []u8,
            flags: []SimpleGlyphFlag,
            x_coordinates: []i16,
            y_coordinates: []i16,

            fn deinit(self: *const SimpleGlyph, allocator: std.mem.Allocator) void {
                allocator.free(self.end_pts_of_contours);
                allocator.free(self.instructions);
                allocator.free(self.flags);
                allocator.free(self.x_coordinates);
                allocator.free(self.y_coordinates);
            }
        };

        fn readCommon(self: GlyfTable, start: usize) Common {
            return help.parse(Common, self.bytes[start .. start + @bitSizeOf(Common) / 8]);
        }

        fn readSimple(self: GlyfTable, allocator: std.mem.Allocator, start: usize, end: usize) !SimpleGlyph {
            var stream = help.Stream{ .data = self.bytes[start..end] };
            const common = stream.readVal(Common);
            const end_pts_of_contours = try stream.readArray(u16, allocator, @intCast(common.number_of_contours));
            errdefer allocator.free(end_pts_of_contours);

            const instruction_length = stream.readVal(u16);
            const instructions = try stream.readArray(u8, allocator, instruction_length);
            errdefer allocator.free(instructions);

            const num_contours = end_pts_of_contours[end_pts_of_contours.len - 1] + 1;

            const flags = try allocator.alloc(SimpleGlyphFlag, num_contours);
            errdefer allocator.free(flags);

            var i: usize = 0;
            while (i < num_contours) {
                defer i += 1;
                const flag_u8 = stream.readVal(u8);
                const flag: SimpleGlyphFlag = @bitCast(flag_u8);
                std.debug.assert(flag.reserved == false);

                flags[i] = flag;

                if (flag.repeat_flag) {
                    const num_repetitions = stream.readVal(u8);
                    @memset(flags[i + 1 .. i + 1 + num_repetitions], flag);
                    i += num_repetitions;
                }
            }

            const x_coords = try allocator.alloc(i16, num_contours);
            errdefer allocator.free(x_coords);
            for (flags, 0..) |flag, idx| {
                const parse_variant = GlyphParseVariant.fromBools(flag.x_short_vector, flag.x_is_same_or_positive_x_short_vector);
                switch (parse_variant) {
                    .short_pos => x_coords[idx] = stream.readVal(u8),
                    .short_neg => x_coords[idx] = -@as(i16, stream.readVal(u8)),
                    .long => x_coords[idx] = stream.readVal(i16),
                    .repeat => x_coords[idx] = 0,
                }
            }

            const y_coords = try allocator.alloc(i16, num_contours);
            errdefer allocator.free(y_coords);
            for (flags, 0..) |flag, idx| {
                const parse_variant = GlyphParseVariant.fromBools(flag.y_short_vector, flag.y_is_same_or_positive_y_short_vector);
                switch (parse_variant) {
                    .short_pos => y_coords[idx] = stream.readVal(u8),
                    .short_neg => y_coords[idx] = -@as(i16, stream.readVal(u8)),
                    .long => y_coords[idx] = stream.readVal(i16),
                    .repeat => y_coords[idx] = 0,
                }
            }

            return .{
                .common = common,
                .end_pts_of_contours = end_pts_of_contours,
                .instruction_length = instruction_length,
                .instructions = instructions,
                .flags = flags,
                .x_coordinates = x_coords,
                .y_coordinates = y_coords,
            };
        }
    };

    head: HeadTable,
    cmap: CmapTable,
    glyf: GlyfTable,
    loca: []const u32,

    allocator: std.mem.Allocator,

    pub fn load(allocator: std.mem.Allocator, bytes: []const u8) !Self {
        const offset_size = @bitSizeOf(OffsetTable) / 8;
        std.debug.assert(@sizeOf(TableEntry) == @bitSizeOf(TableEntry) / 8);

        const offsets = help.parse(OffsetTable, bytes[0..offset_size]);
        const table_start = offset_size;
        const table_end = table_start + @sizeOf(TableEntry) * offsets.num_tables;
        const tables = std.mem.bytesAsSlice(TableEntry, bytes[table_start..table_end]);

        var head: ?HeadTable = null;
        var loca: ?[]const u32 = null;
        var cmap: ?CmapTable = null;
        var glyf: ?GlyfTable = null;

        for (tables) |big| {
            const table = help.fix(big);
            const tag = std.meta.stringToEnum(Tag, &table.tag) orelse {
                std.log.warn("unknown tag: {s}", .{table.tag});
                continue;
            };

            switch (tag) {
                .head => head = help.parse(HeadTable, table.get(bytes)),
                .loca => loca = try help.fixSlice(u32, allocator, @alignCast(std.mem.bytesAsSlice(u32, table.get(bytes)))),
                .cmap => cmap = .{ .bytes = table.get(bytes) },
                .glyf => glyf = .{ .bytes = table.get(bytes) },
            }
        }

        return .{
            .head = head orelse return error.MissingTable,
            .cmap = cmap orelse return error.MissingTable,
            .glyf = glyf orelse return error.MissingTable,
            .loca = loca orelse return error.MissingTable,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.loca);
    }

    pub fn readSubtable(self: *const Self) !CmapTable.Format4 {
        assert(self.head.index_to_loc_format == 1);
        assert(self.head.magic_number == 0x5F0F3CF5);

        const index = self.cmap.readIndex();
        const offset = blk: {
            for (0..index.num_subtables) |i| {
                const subtable = self.cmap.readSubtable(i);
                if (subtable.isUnicode()) {
                    break :blk subtable.offset;
                }
            }

            return error.NoUnicodeSubtable;
        };

        const format = self.cmap.subTableFormat(offset);
        assert(format == 4);

        return try self.cmap.readFormat4(self.allocator, offset);
    }

    pub fn glyphForChar(self: *const Self, subtable: *const CmapTable.Format4, char: u16) !GlyfTable.SimpleGlyph {
        const glyph_index = subtable.getGlyphIndex(char);
        const start = self.loca[glyph_index];
        const end = self.loca[glyph_index + 1];

        const header = self.glyf.readCommon(start);
        std.log.debug("glyph header: {any}", .{header});
        assert(header.number_of_contours != 0);

        return try self.glyf.readSimple(self.allocator, start, end);
    }
};

const help = struct {
    fn parse(comptime T: type, bytes: []const u8) T {
        const raw = std.mem.bytesToValue(T, bytes);
        return fix(raw);
    }

    fn fix(data_: anytype) @TypeOf(data_) {
        var data = data_;
        if (builtin.cpu.arch.endian() == .little) {
            switch (@typeInfo(@TypeOf(data_))) {
                .@"struct" => std.mem.byteSwapAllFields(@TypeOf(data_), &data),
                .int => data = std.mem.bigToNative(@TypeOf(data_), data),
                else => comptime unreachable,
            }
        }
        return data;
    }

    fn fixSlice(comptime T: type, allocator: std.mem.Allocator, slice: []const T) ![]T {
        const duped = try allocator.alloc(T, slice.len);
        for (0..slice.len) |i| {
            duped[i] = fix(slice[i]);
        }
        return duped;
    }

    const Stream = struct {
        data: []const u8,
        idx: usize = 0,

        pub fn readVal(self: *Stream, comptime T: type) T {
            const size = @bitSizeOf(T) / 8;
            defer self.idx += size;

            return parse(T, self.data[self.idx .. self.idx + size]);
        }

        pub fn readArray(self: *Stream, comptime T: type, alloc: std.mem.Allocator, len: usize) ![]T {
            const size = @bitSizeOf(T) / 8 * len;
            defer self.idx += size;

            return fixSlice(T, alloc, @alignCast(std.mem.bytesAsSlice(T, self.data[self.idx .. self.idx + size])));
        }
    };
};

test TTF {
    const data = try std.fs.cwd().readFileAlloc(testing.allocator, "FiraGO-Regular.ttf", 0x100000000);
    defer testing.allocator.free(data);

    const font = try TTF.load(testing.allocator, data);
    defer font.deinit();

    const table = try font.readSubtable();
    defer table.deinit(testing.allocator);

    const glyph = try font.glyphForChar(&table, 'A');
    defer glyph.deinit(testing.allocator);
}
