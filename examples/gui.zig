const std = @import("std");
const gfx = @import("gfx");
const ui = gfx.oui;

const allocator = std.heap.page_allocator;

pub fn main() !void {
    const ctx = try ui.Context.create(allocator, 4096, 1 << 20);
    defer ctx.deinit();

    ctx.makeCurrent();
    ui.setHandler(ui_handler);

    // while (app_running()) {
    //     // update position of mouse cursor; the ui can also be updated
    //     // from received events.
    //     uiSetCursor(app_get_mouse_x(), app_get_mouse_y());

    //     // update button state
    //     for (0..3) |i|
    //         uiSetButton(i, app_get_button_state(i));

    //     // you can also send keys and scroll events; see example.cpp for more

    // --------------
    // this section does not have to be regenerated on frame; a good
    // policy is to invalidate it on events, as this usually alters
    // structure and layout.

    // begin new UI declarations
    ui.beginLayout();

    // - UI setup code goes here -
    layout_window(400, 300);

    // layout UI
    ui.endLayout();

    // --------------

    //     // draw UI, starting with the first item, index 0
    //     app_draw_ui(render_context, 0);

    //     // update states and fire handlers
    //     uiProcess(get_time_ms());
    // }

    var timer = try std.time.Timer.start();
    while (true) {
        draw_ui(.root);
        ui.Process(timer.lap() / std.time.ns_per_ms);
    }
}

fn draw_ui(id: ui.Id) void {
    if (ui.GetHandle(Header, id)) |head| {
        std.debug.print("header: {any}\n", .{head});
    }

    var kid = ui.firstChild(id);
    while (kid != .invalid) {
        draw_ui(kid);
        kid = ui.nextSibling(kid);
    }
}

fn ui_handler(_: ui.Id, _: ui.Event) void {
    unreachable;
}

// zig fmt: off
fn layout_window(w: i16, h: i16) void {
    const root = ui.newItem();                    // create root item; the first item always has index 0
    ui.setSize(root, w, h);                           // assign fixed size

    const parent = ui.insert(root, ui.newItem()); // create column box
    ui.setBox(parent, ui.COLUMN);                     // configure as column
    ui.setLayout(parent, ui.HFILL | ui.TOP);          // span horizontally, attach to top

    const static = struct {
        var checked: bool = false;
    };

    const item = ui.insert(parent, Checkbox.create("Checked:", &static.checked));
    ui.setSize(item, 0, 10);
    ui.setLayout(item, ui.HFILL);
}
// zig fmt: on

const Header = struct {
    kind: u32,
    handler: ui.Handler,
};

const Checkbox = struct {
    head: Header,
    label: []const u8,
    checked: *bool,

    comptime {
        std.debug.assert(@offsetOf(Checkbox, "head") == 0);
    }

    fn create(label: []const u8, checked: *bool) ui.Id {
        const item = ui.newItem();
        ui.setSize(item, 0, 10);

        ui.allocHandle(Checkbox, item).* = .{
            .head = .{
                .kind = 1,
                .handler = Checkbox.handler,
            },
            .label = label,
            .checked = checked,
        };

        // TODO set events

        return item;
    }

    fn handler(id: ui.Id, _: ui.Event) void {
        const self = ui.GetHandle(Checkbox, id).?;
        self.checked.* = !self.checked.*;
    }
};
