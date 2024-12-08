const std = @import("std");
const assert = std.debug.assert;

pub fn Pool(comptime K: type, comptime V: type) type {
    assert(@bitSizeOf(K) == @bitSizeOf(u16));

    return struct {
        const Self = @This();

        items: []V,
        handles: Handles(K, u8, u8),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return .{
                .items = try allocator.alloc(V, capacity),
                .handles = try .init(allocator, capacity),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
            self.handles.deinit();
        }

        pub fn add(self: *Self, item: V) K {
            const handle = self.handles.create();
            self.items[self.handles.extractIndex(handle)] = item;
            return handle;
        }

        pub fn get(self: *Self, id: K) *V {
            assert(self.handles.alive(id));
            return &self.items[self.handles.extractIndex(id)];
        }

        pub fn remove(self: *Self, id: K) *V {
            assert(self.handles.alive(id));
            const obj = &self.items.items[self.handles.extractIndex(id)];
            self.handles.destroy(id);
            return obj;
        }
    };
}

pub fn Handles(comptime HandleType: type, comptime IndexType: type, comptime VersionType: type) type {
    const HandleRaw = @typeInfo(HandleType).@"enum".tag_type;

    assert(@bitSizeOf(IndexType) + @bitSizeOf(VersionType) == @bitSizeOf(HandleRaw));

    return struct {
        const Self = @This();

        handles: []HandleType,
        append_cursor: IndexType = 1,
        last_destroyed: ?IndexType = null,
        allocator: std.mem.Allocator,

        const invalid = std.math.maxInt(IndexType);

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return .{ .handles = try allocator.alloc(HandleType, capacity), .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.handles);
        }

        pub fn create(self: *Self) HandleType {
            if (self.last_destroyed) |last| {
                const version = self.extractVersion(self.handles[last]);
                const destroyed_id = self.extractIndex(self.handles[last]);

                const handle = forge(last, version);
                self.handles[last] = @enumFromInt(handle);

                self.last_destroyed = if (destroyed_id == invalid) null else destroyed_id;
                return @enumFromInt(handle);
            } else {
                assert(self.handles.len - 1 != self.append_cursor);

                const idx = self.append_cursor;
                const handle = forge(self.append_cursor, 0);
                self.handles[idx] = @enumFromInt(handle);

                self.append_cursor += 1;
                return @enumFromInt(handle);
            }
        }

        pub fn destroy(self: *Self, handle: HandleType) void {
            const id = self.extractIndex(handle);
            const next_id = self.last_destroyed orelse invalid;
            assert(next_id != id);

            const version = self.extractVersion(handle);
            self.handles[id] = forge(next_id, version +% 1);

            self.last_destroyed = id;
        }

        pub fn alive(self: *const Self, handle: HandleType) bool {
            const idx = self.extractIndex(handle);
            return idx < self.append_cursor and self.handles[idx] == handle;
        }

        pub fn extractIndex(_: *const Self, handle: HandleType) IndexType {
            return @truncate(@intFromEnum(handle));
        }

        pub fn extractVersion(_: *const Self, handle: HandleType) VersionType {
            return @truncate(@as(HandleRaw, @intFromEnum(handle)) >> @bitSizeOf(IndexType));
        }

        fn forge(idx: IndexType, version: VersionType) HandleRaw {
            return @as(HandleRaw, idx) | @as(HandleRaw, version) << @bitSizeOf(IndexType);
        }
    };
}
