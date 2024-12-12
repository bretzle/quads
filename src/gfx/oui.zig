const std = @import("std");
const quads = @import("quads");

const assert = std.debug.assert;

/// maximum size in bytes of a single data buffer passed to uiAllocData().
pub const max_datasize = 4096;
/// maximum depth of nested containers
pub const max_depth = 64;
/// maximum number of buffered input events
pub const max_input_events = 64;
/// consecutive click threshold in ms
pub const click_threshold = 250;

// bit 0-2
const BOX_MODEL_MASK: u32 = 0x000007;
// bit 0-4
const BOX_MASK: u32 = 0x00001F;
// bit 5-8
const LAYOUT_MASK: u32 = 0x0003E0;
// bit 9-18
const EVENT_MASK: u32 = 0x07FC00;
// item is frozen (bit 19)
const FROZEN: u32 = 0x080000;
// item handle is pointer to data (bit 20)
const DATA: u32 = 0x100000;
// item has been inserted (bit 21)
const INSERTED: u32 = 0x200000;
// horizontal size has been explicitly set (bit 22)
const HFIXED: u32 = 0x400000;
// vertical size has been explicitly set (bit 23)
const VFIXED: u32 = 0x800000;
// bit 22-23
const FIXED_MASK: u32 = 0xC00000;

// flex-direction (bit 0+1)

// left to right
pub const ROW: u32 = 0x002;
// top to bottom
pub const COLUMN: u32 = 0x003;

// model (bit 1)

// free layout
pub const LAYOUT: u32 = 0x000;
// flex model
pub const FLEX: u32 = 0x002;

// flex-wrap (bit 2)

// single-line
pub const NOWRAP: u32 = 0x000;
// multi-line, wrap left to right
pub const WRAP: u32 = 0x004;

// justify-content (start, end, center, space-between)
// at start of row/column
pub const START: u32 = 0x008;
// at center of row/column
pub const MIDDLE: u32 = 0x000;
// at end of row/column
pub const END: u32 = 0x010;
// insert spacing to stretch across whole row/column
pub const JUSTIFY: u32 = 0x018;

// align-items
// can be implemented by putting a flex container in a layout container,
// then using UI_TOP, UI_DOWN, UI_VFILL, UI_VCENTER, etc.
// FILL is equivalent to stretch/grow

// align-content (start, end, center, stretch)
// can be implemented by putting a flex container in a layout container,
// then using UI_TOP, UI_DOWN, UI_VFILL, UI_VCENTER, etc.
// FILL is equivalent to stretch; space-between is not supported.

// attachments (bit 5-8)
// fully valid when parent uses UI_LAYOUT model
// partially valid when in UI_FLEX model

// anchor to left item or left side of parent
pub const LEFT: u32 = 0x020;
// anchor to top item or top side of parent
pub const TOP: u32 = 0x040;
// anchor to right item or right side of parent
pub const RIGHT: u32 = 0x080;
// anchor to bottom item or bottom side of parent
pub const DOWN: u32 = 0x100;
// anchor to both left and right item or parent borders
pub const HFILL: u32 = 0x0a0;
// anchor to both top and bottom item or parent borders
pub const VFILL: u32 = 0x140;
// center horizontally, with left margin as offset
pub const HCENTER: u32 = 0x000;
// center vertically, with top margin as offset
pub const VCENTER: u32 = 0x000;
// center in both directions, with left/top margin as offset
pub const CENTER: u32 = 0x000;
// anchor to all four directions
pub const FILL: u32 = 0x1e0;
// when wrapping, put this element on a new line
// wrapping layout code auto-inserts UI_BREAK flags,
// drawing routines can read them with uiGetLayout()
pub const BREAK: u32 = 0x200;

const UI_USERMASK: u32 = 0xff000000;
const UI_ANY: u32 = 0xffffffff;

// on button 0 down
const UI_BUTTON0_DOWN: u32 = 0x0400;
// on button 0 up
// when this event has a handler, uiGetState() will return UI_ACTIVE as
// long as button 0 is down.
const UI_BUTTON0_UP: u32 = 0x0800;
// on button 0 up while item is hovered
// when this event has a handler, uiGetState() will return UI_ACTIVE
// when the cursor is hovering the items rectangle; this is the
// behavior expected for buttons.
const UI_BUTTON0_HOT_UP: u32 = 0x1000;
// item is being captured (button 0 constantly pressed);
// when this event has a handler, uiGetState() will return UI_ACTIVE as
// long as button 0 is down.
const UI_BUTTON0_CAPTURE: u32 = 0x2000;
// on button 2 down (right mouse button, usually triggers context menu)
const UI_BUTTON2_DOWN: u32 = 0x4000;
// item has received a scrollwheel event
// the accumulated wheel offset can be queried with uiGetScroll()
const UI_SCROLL: u32 = 0x8000;
// item is focused and has received a key-down event
// the respective key can be queried using uiGetKey() and uiGetModifier()
const UI_KEY_DOWN: u32 = 0x10000;
// item is focused and has received a key-up event
// the respective key can be queried using uiGetKey() and uiGetModifier()
const UI_KEY_UP: u32 = 0x20000;
// item is focused and has received a character event
// the respective character can be queried using uiGetKey()
const UI_CHAR: u32 = 0x40000;

const UI_ANY_BUTTON0_INPUT = (UI_BUTTON0_DOWN | UI_BUTTON0_UP | UI_BUTTON0_HOT_UP | UI_BUTTON0_CAPTURE);
const UI_ANY_BUTTON2_INPUT = (UI_BUTTON2_DOWN);
const UI_ANY_MOUSE_INPUT = (UI_ANY_BUTTON0_INPUT | UI_ANY_BUTTON2_INPUT);
const UI_ANY_KEY_INPUT = (UI_KEY_DOWN | UI_KEY_UP | UI_CHAR);
const UI_ANY_INPUT = (UI_ANY_MOUSE_INPUT | UI_ANY_KEY_INPUT);

pub const ItemState = enum {
    /// the item is inactive
    cold,
    /// the item is inactive, but the cursor is hovering over this item
    hot,
    /// the item is toggled, activated, focused (depends on item kind)
    active,
    /// the item is unresponsive
    frozen,
};

// TODO UIboxFlags
// TODO UIlayoutFlags
// TODO UIevent
pub const Event = void;

// TODO UIhandler
pub const Handler = *const fn (Id, Event) void;

pub const Vec2 = [2]i32;
pub const Rect = [4]i32;

pub const Id = enum(u32) {
    invalid = 0xFFFF_FFFF,
    root = 0,
    _,
};

var valid = false;
var ui: *Context = undefined;

const State = enum { idle, capture };
const Stage = enum { layout, post_layout, process };

const HandleEntry = struct {
    key: u32,
    item: Id,
};

const InputEvent = struct {
    key: u32,
    mod: u32,
    event: Event,
};

const Item = struct {
    handle: ?*anyopaque = null,

    flags: u32 = 0,

    firstkid: Id,
    nextitem: Id,

    margins: [4]i16 = .{ 0, 0, 0, 0 },
    size: [2]i16 = .{ 0, 0 },
};

pub const Context = struct {
    item_capacity: u32,
    buffer_capacity: u32,

    handler: Handler = undefined,

    buttons: u64 = 0,
    last_buttons: u64 = 0,

    start_cursor: Vec2 = .{ 0, 0 },
    last_cursor: Vec2 = .{ 0, 0 },
    cursor: Vec2 = .{ 0, 0 },
    scroll: Vec2 = .{ 0, 0 },

    active_item: Id = .invalid,
    focus_item: Id = .invalid,
    last_hot_item: Id = .invalid,
    last_click_item: Id = .invalid,
    hot_item: Id = .invalid,

    state: State = .idle,
    stage: Stage,
    active_key: u32 = 0,
    active_modifier: u32 = 0,
    active_button_modifier: u32 = 0,
    last_timestamp: u64 = 0,
    last_click_timestamp: i32 = 0,
    clicks: i32 = 0,

    count: u32 = 0,
    last_count: u32 = 0,
    eventcount: u32 = 0,
    datasize: u32 = 0,

    items: []Item,
    data: []u8,
    last_items: []Item,
    item_map: []Id,
    events: [max_input_events]InputEvent = undefined,

    allocator: std.mem.Allocator,

    /// create a new UI context; call makeCurrent() to make this context the
    /// current context. The context is managed by the client and must be released
    /// using destroy()
    ///
    /// `item_capacity` is the maximum of number of items that can be declared.
    /// `buffer_capacity` is the maximum total size of bytes that can be allocated using uiAllocHandle(); you may pass 0 if you don't need to allocate handles.
    ///
    /// 4096 and (1<<20) are good starting values.
    pub fn create(allocator: std.mem.Allocator, item_capacity: u32, buffer_capacity: u32) !*Context {
        assert(item_capacity != 0);
        const ctx = try allocator.create(Context);

        ctx.* = .{
            .item_capacity = item_capacity,
            .buffer_capacity = buffer_capacity,
            .stage = .process,
            .items = try allocator.alloc(Item, item_capacity),
            .last_items = try allocator.alloc(Item, item_capacity),
            .item_map = try allocator.alloc(Id, item_capacity),
            .data = try allocator.alloc(u8, buffer_capacity),
            .allocator = allocator,
        };

        const old = ui;
        ctx.makeCurrent();
        clear();
        clearState();
        old.makeCurrent();

        return ctx;
    }

    /// release the memory of an UI context created with Context.create(); if the
    /// context is the current context, the current context will be set to null
    pub fn deinit(ctx: *Context) void {
        if (ui == ctx) makeCurrent(null);
        ctx.allocator.free(ctx.items);
        ctx.allocator.free(ctx.last_items);
        ctx.allocator.free(ctx.item_map);
        ctx.allocator.free(ctx.data);
        ctx.allocator.destroy(ctx);
    }

    /// select an UI context as the current context; a context must always be
    /// selected before using any of the other UI functions
    pub fn makeCurrent(ctx: ?*Context) void {
        if (ctx) |new| {
            ui = new;
            valid = true;
        } else {
            ui = undefined;
            valid = false;
        }
    }

    /// returns the currently selected context or null
    pub fn get() ?*Context {
        return if (valid) ui else null;
    }
};

// TODO input control

// TODO stages

/// clear the item buffer; uiBeginLayout() should be called before the first
/// UI declaration for this frame to avoid concatenation of the same UI multiple
/// times.
/// After the call, all previously declared item IDs are invalid, and all
/// application dependent context data has been freed.
/// uiBeginLayout() must be followed by uiEndLayout().
pub fn beginLayout() void {
    assert(valid);
    assert(ui.stage == .process); // must run endLayout(), process() first
    clear();
    ui.stage = .layout;
}

/// layout all added items starting from the root item 0.
/// after calling uiEndLayout(), no further modifications to the item tree should
/// be done until the next call to uiBeginLayout().
/// It is safe to immediately draw the items after a call to uiEndLayout().
/// this is an O(N) operation for N = number of declared items.
pub fn endLayout() void {
    assert(valid);
    assert(ui.stage == .layout); // must run beginLayout() first

    if (ui.count != 0) {
        computeSize(Id.root, 0);
        arrange(Id.root, 0);
        computeSize(Id.root, 1);
        arrange(Id.root, 1);

        if (ui.last_count != 0) unreachable;
    }

    validateStateItems();
    if (ui.count != 0) {
        // drawing routines may require this to be set already
        updateHotItem();
    }

    ui.stage = .post_layout;
}

/// update the current hot item; this only needs to be called if items are kept
/// for more than one frame and uiEndLayout() is not called
pub fn updateHotItem() void {
    assert(valid);
    if (ui.count == 0) return;
    ui.hot_item = findItem(Id.root, ui.cursor[0], ui.cursor[1], UI_ANY_MOUSE_INPUT, UI_ANY);
}

/// update the internal state according to the current cursor position and
/// button states, and call all registered handlers.
/// timestamp is the time in milliseconds relative to the last call to uiProcess()
/// and is used to estimate the threshold for double-clicks
/// after calling uiProcess(), no further modifications to the item tree should
/// be done until the next call to uiBeginLayout().
/// Items should be drawn before a call to uiProcess()
/// this is an O(N) operation for N = number of declared items.
pub fn Process(timestamp: u64) void {
    assert(valid);
    assert(ui.stage != .layout);

    if (ui.stage == .process) updateHotItem();
    ui.stage = .process;

    if (ui.count == 0) {
        unreachable;
    }

    var hot_item = ui.last_hot_item;
    const active_item = ui.active_item;
    const focus_item = ui.focus_item;

    if (focus_item != .invalid) {
        unreachable;
    } else {
        ui.focus_item = .invalid;
    }

    if (ui.scroll[0] != 0 or ui.scroll[1] != 0) {
        unreachable;
    }

    clearInputEvents();

    const hot = ui.hot_item;

    switch (ui.state) {
        .idle => {
            ui.start_cursor = ui.cursor;
            // TODO GetButton
            hot_item = hot;
        },
        .capture => unreachable,
    }

    ui.last_cursor = ui.cursor;
    ui.last_hot_item = hot_item;
    ui.active_item = active_item;

    ui.last_timestamp = timestamp;
    ui.last_buttons = ui.buttons;
}

/// reset the currently stored hot/active etc. handles; this should be called when
/// a re-declaration of the UI changes the item indices, to avoid state
/// related glitches because item identities have changed.
pub fn clearState() void {
    ui.last_hot_item = .invalid;
    ui.active_item = .invalid;
    ui.focus_item = .invalid;
    ui.last_click_item = .invalid;
}

// TODO UI declaration

pub fn newItem() Id {
    assert(valid);
    assert(ui.stage == .layout);
    assert(ui.count < ui.item_capacity);
    const idx = ui.count;
    ui.count += 1;
    itemPtr(idx).* = .{
        .firstkid = .invalid,
        .nextitem = .invalid,
    };
    return @enumFromInt(idx);
}

/// assign an item to a container.
/// an item ID of 0 refers to the root item.
/// the function returns the child item ID
/// if the container has already added items, the function searches
/// for the last item and calls uiAppend() on it, which is an
/// O(N) operation for N siblings.
/// it is usually more efficient to call uiInsert() for the first child,
/// then chain additional siblings using uiAppend().
pub fn insert(parent: Id, child: Id) Id {
    assert(@as(u32, @intFromEnum(child)) > 0);

    const pparent = itemPtr(@intFromEnum(parent));
    const pchild = itemPtr(@intFromEnum(child));

    assert(pchild.flags & INSERTED == 0);

    if (pparent.firstkid == .invalid) {
        pparent.firstkid = child;
        pchild.flags |= INSERTED;
    } else {
        unreachable;
    }

    return child;
}

/// set the size of the item; a size of 0 indicates the dimension to be
/// dynamic; if the size is set, the item can not expand beyond that size.
pub fn setSize(id: Id, w: i16, h: i16) void {
    const item = itemPtr(@intFromEnum(id));
    item.size = .{ w, h };

    if (w != 0) item.flags &= ~HFIXED else item.flags |= HFIXED;
    if (h != 0) item.flags &= ~VFIXED else item.flags |= VFIXED;
}

/// set the anchoring behavior of the item to one or multiple UIlayoutFlags
pub fn setLayout(id: Id, flags: u32) void {
    const item = itemPtr(@intFromEnum(id));
    assert(flags & LAYOUT_MASK == flags);
    item.flags &= ~LAYOUT_MASK;
    item.flags |= flags & LAYOUT_MASK;
}

/// set the box model behavior of the item to one or multiple UIboxFlags
pub fn setBox(id: Id, flags: u32) void {
    const item = itemPtr(@intFromEnum(id));
    assert(flags & BOX_MASK == flags);
    item.flags &= ~BOX_MASK;
    item.flags |= flags & BOX_MASK;
}

/// allocate space for application-dependent context data and assign it
/// as the handle to the item.
/// The memory of the pointer is managed by the UI context and released
/// upon the next call to uiBeginLayout()
pub fn allocHandle(comptime T: type, id: Id) *T {
    const size = @sizeOf(T);
    assert(size < max_datasize);
    const item = itemPtr(@intFromEnum(id));
    assert(item.handle == null);
    assert(ui.datasize + size <= ui.buffer_capacity);
    item.handle = @ptrCast(&ui.data[ui.datasize]);
    item.flags |= DATA;
    ui.datasize += size;
    return @alignCast(@ptrCast(item.handle.?));
}

/// set the global handler callback for interactive items.
/// the handler will be called for each item whose event flags are set using
/// uiSetEvents.
pub fn setHandler(handler: Handler) void {
    ui.handler = handler;
}

//#region iteration

/// returns the first child item of a container item. If the item is not
/// a container or does not contain any items, -1 is returned.
/// if item is 0, the first child item of the root item will be returned.
pub fn firstChild(id: Id) Id {
    return itemPtr(@intFromEnum(id)).firstkid;
}

/// returns an items next sibling in the list of the parent containers children.
/// if item is 0 or the item is the last child item, -1 will be returned.
pub fn nextSibling(id: Id) Id {
    return itemPtr(@intFromEnum(id)).nextitem;
}

//#endregion

// TODO querying

pub fn getHandler() ?Handler {
    unreachable;
}

/// return the application-dependent handle of the item as passed to uiSetHandle()
/// or uiAllocHandle().
pub fn GetHandle(comptime T: type, id: Id) ?*T {
    return @alignCast(@ptrCast(itemPtr(@intFromEnum(id)).handle));
}

/// returns the topmost item containing absolute location (x,y), starting with
/// item as parent, using a set of flags and masks as filter:
/// if both flags and mask are UI_ANY, the first topmost item is returned.
/// if mask is UI_ANY, the first topmost item matching *any* of flags is returned.
/// otherwise the first item matching (item.flags & flags) == mask is returned.
/// you may combine box, layout, event and user flags.
/// frozen items will always be ignored.
pub fn findItem(id: Id, x: i32, y: i32, flags: u32, mask: u32) Id {
    const pitem = itemPtr(@intFromEnum(id));
    if (pitem.flags & FROZEN != 0) return .invalid;

    if (contains(id, x, y)) {
        var best_hit = Id.invalid;

        var kid = firstChild(id);
        while (kid != .invalid) {
            const hit = findItem(kid, x, y, flags, mask);
            if (hit != .invalid) {
                best_hit = hit;
            }
            kid = nextSibling(kid);
        }

        if (best_hit != .invalid) {
            return best_hit;
        }

        if (((mask == UI_ANY) and ((flags == UI_ANY) or (pitem.flags & flags != 0))) or (pitem.flags & flags == mask)) {
            return id;
        }
    }

    return .invalid;
}

pub fn contains(id: Id, x: i32, y: i32) bool {
    const rect = getRect(id);
    const xx = x - rect[0];
    const yy = y - rect[1];
    return (xx >= 0) and (yy >= 0) and (xx < rect[2]) and (yy < rect[3]);
}

/// when uiBeginLayout() is called, the most recently declared items are retained.
/// when uiEndLayout() completes, it matches the old item hierarchy to the new one
/// and attempts to map old items to new items as well as possible.
/// when passed an item Id from the previous frame, uiRecoverItem() returns the
/// items new assumed Id, or -1 if the item could not be mapped.
/// it is valid to pass -1 as item.
pub fn recoverItem(olditem: Id) Id {
    assert(valid);
    if (olditem == .invalid) return .invalid;
    return ui.item_map[@intFromEnum(olditem)];
}

/// returns the items layout rectangle in absolute coordinates. If
/// uiGetRect() is called before uiEndLayout(), the values of the returned
/// rectangle are undefined.
pub fn getRect(id: Id) Rect {
    const item = itemPtr(@intFromEnum(id));
    return .{ item.margins[0], item.margins[1], item.size[0], item.size[1] };
}

// TODO inner

fn clear() void {
    ui.last_count = ui.count;
    ui.count = 0;
    ui.datasize = 0;
    ui.hot_item = .invalid;

    // swap buffers
    std.mem.swap([]Item, &ui.items, &ui.last_items);
    @memset(ui.item_map[0..ui.last_count], .invalid);
}

fn validateStateItems() void {
    assert(valid);
    ui.last_hot_item = recoverItem(ui.last_hot_item);
    ui.active_item = recoverItem(ui.active_item);
    ui.focus_item = recoverItem(ui.focus_item);
    ui.last_click_item = recoverItem(ui.last_click_item);
}

fn itemPtr(idx: u32) *Item {
    assert(valid);
    assert(idx >= 0 and idx < ui.count);
    return &ui.items[idx];
}

fn computeSize(id: Id, dim: u1) void {
    const item = itemPtr(@intFromEnum(id));

    var kid = item.firstkid;
    while (kid != .invalid) {
        computeSize(kid, dim);
        kid = nextSibling(kid);
    }

    if (item.size[dim] != 0) return;

    switch (item.flags & BOX_MODEL_MASK) {
        COLUMN | WRAP => unreachable,
        ROW | WRAP => unreachable,
        COLUMN, ROW => {
            // flex model
            if (item.flags & 1 == dim)
                unreachable
            else
                computeImposedSize(item, 1);
        },
        else => computeImposedSize(item, dim),
    }
}

/// compute bounding box of all items super-imposed
fn computeImposedSize(item: *Item, dim: u2) void {
    const wdim = dim + 2;

    var need_size: i16 = 0;
    var kid = item.firstkid;
    while (kid != .invalid) {
        const pkid = itemPtr(@intFromEnum(kid));

        const kidsize = pkid.margins[dim] + pkid.size[dim] + pkid.margins[wdim];
        need_size = @max(need_size, kidsize);
        kid = nextSibling(kid);
    }

    item.size[dim] = need_size;
}

fn arrange(id: Id, dim: u1) void {
    const item = itemPtr(@intFromEnum(id));

    switch (item.flags & BOX_MODEL_MASK) {
        COLUMN | WRAP => unreachable,
        ROW | WRAP => unreachable,
        COLUMN, ROW => {
            // flex model
            if (item.flags & 1 == dim)
                arrangeStacked(item, dim, false)
            else
                arrangeImposedSqueezed(item, dim);
        },
        else => {
            // layout model
            arrangeImposed(item, dim);
        },
    }

    var kid = firstChild(id);
    while (kid != .invalid) {
        arrange(kid, dim);
        kid = nextSibling(kid);
    }
}

fn arrangeImposed(item: *Item, dim: u1) void {
    arrangeImposedRange(item, dim, item.firstkid, .invalid, item.margins[dim], item.size[dim]);
}

fn arrangeImposedRange(item: *Item, dim: u2, start_kid: Id, end_kid: Id, offset: i16, space: i16) void {
    const wdim = dim + 2;
    _ = item;

    var kid = start_kid;
    while (kid != end_kid) {
        const pkid = itemPtr(@intFromEnum(kid));

        const flags = (pkid.flags & LAYOUT_MASK) >> dim;
        switch (flags & HFILL) {
            HCENTER => unreachable,
            RIGHT => unreachable,
            HFILL => pkid.size[dim] = @max(0, space - pkid.margins[dim] - pkid.margins[wdim]),
            else => {},
        }

        pkid.margins[dim] += offset;
        kid = nextSibling(kid);
    }
}

fn arrangeImposedSqueezed(item: *Item, dim: u1) void {
    arrangeImposedSqueezedRange(item, dim, item.firstkid, .invalid, item.margins[dim], item.size[dim]);
}

fn arrangeImposedSqueezedRange(_: *Item, dim: u2, start_kid: Id, end_kid: Id, offset: i16, space: i16) void {
    const wdim = dim + 2;

    var kid = start_kid;
    while (kid != end_kid) {
        const pkid = itemPtr(@intFromEnum(kid));

        const min_size = @max(0, space - pkid.margins[dim] - pkid.margins[wdim]);
        const flags = (pkid.flags & LAYOUT_MASK) >> dim;
        switch (flags & HFILL) {
            HCENTER => unreachable,
            RIGHT => unreachable,
            HFILL => pkid.size[dim] = min_size,
            else => unreachable,
        }

        pkid.margins[dim] += offset;
        kid = nextSibling(kid);
    }
}

/// stack all items according to their alignment
fn arrangeStacked(item: *Item, dim: u2, wrap: bool) void {
    const wdim = dim + 2;

    const space = item.size[dim];
    const max_x2: f32 = @as(f32, @floatFromInt(item.margins[dim])) + @as(f32, @floatFromInt(space));

    var start_kid = item.firstkid;
    while (start_kid != .invalid) {
        var used: i16 = 0;
        const count: u32 = 0;
        var squeezed_count: u32 = 0;
        var total: u32 = 0;
        const hardbreak = false;
        _ = hardbreak; // autofix

        var kid = start_kid;
        const end_kid = Id.invalid;
        while (kid != .invalid) {
            const pkid = itemPtr(@intFromEnum(kid));
            const flags = (pkid.flags & LAYOUT_MASK) >> dim;
            const fflags = (pkid.flags & FIXED_MASK) >> dim;
            var extend = used;

            if (flags & HFILL == HFILL) {
                unreachable;
            } else {
                if (fflags & HFIXED != HFIXED)
                    squeezed_count += 1;
                extend += pkid.margins[dim] + pkid.size[dim] + pkid.margins[wdim];
            }

            if (wrap and (total != 0 and ((extend > space) or (pkid.flags & BREAK != 0)))) {
                unreachable;
            } else {
                used = extend;
                kid = nextSibling(kid);
            }

            total += 1;
        }

        const extra_space = space - used;
        const filler: f32 = 0;
        const spacer: f32 = 0;
        var extra_margin: f32 = 0;
        const eater: f32 = 0;

        if (extra_space > 0) {
            if (count != 0) {
                unreachable;
            } else if (total != 0) {
                unreachable;
            }
        } else if (!wrap and (extra_space < 0)) {
            unreachable;
        }

        // distribute width among items
        var x: f32 = @floatFromInt(item.margins[dim]);
        var x1: f32 = 0;
        // second pass: distribute and rescale
        kid = start_kid;
        while (kid != end_kid) {
            // short ix0, ix1;
            const pkid = itemPtr(@intFromEnum(kid));
            const flags = (pkid.flags & LAYOUT_MASK) >> dim;
            const fflags = (pkid.flags & FIXED_MASK) >> dim;

            x += @as(f32, @floatFromInt(pkid.margins[dim])) + extra_margin;
            if (flags & HFILL == HFILL) {
                x1 = x + filler; // grow
            } else if (fflags & HFIXED == HFIXED) {
                x1 = x + @as(f32, @floatFromInt(pkid.size[dim]));
            } else {
                x1 = x + @max(0.0, @as(f32, @floatFromInt(pkid.size[dim])) + eater); // squeeze
            }

            const ix0: i16 = @intFromFloat(x);
            const ix1: i16 = if (wrap)
                @intFromFloat(@min(max_x2 - @as(f32, @floatFromInt(pkid.margins[wdim])), x1))
            else
                @intFromFloat(x1);
            pkid.margins[dim] = ix0;
            pkid.size[dim] = ix1 - ix0;
            x = x1 + @as(f32, @floatFromInt(pkid.margins[wdim]));

            kid = nextSibling(kid);
            extra_margin = spacer;
        }

        start_kid = end_kid;
    }
}

fn clearInputEvents() void {
    assert(valid);
    ui.eventcount = 0;
    ui.scroll = .{ 0, 0 };
}
