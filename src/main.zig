const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const print = std.debug.print;

var pass_action: sg.PassAction = .{};

export fn init() void {
    sg.setup(.{ .environment = sglue.environment(), .logger = .{ .func = slog.func } });
    pass_action.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = 1, .g = 1, .b = 0, .a = 1 } };
    print("Backend: {}\n", .{sg.queryBackend()});
}

export fn frame() void {
    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{ .init_cb = init, .frame_cb = frame, .cleanup_cb = cleanup, .width = 640, .height = 480, .icon = .{ .sokol_default = true }, .window_title = "Zig Game of Life", .logger = .{ .func = slog.func }, .win32_console_attach = true });
}
