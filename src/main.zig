const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;

const shd = @import("shader.glsl.zig");


const print = std.debug.print;
const native_endian = @import("builtin").target.cpu.arch.endian();

const window_width = 1280;
const window_height = 960;
const cell_size: u32 = 32;
const num_cells_x: usize = window_width / cell_size;
const num_cells_y: usize = window_height / cell_size;
const num_total_cells = num_cells_x * num_cells_y;

const background_color = makeColorRGBA8(0x96a6c8ff);
const foreground_color = makeColorRGBA8(0x181818ff);
const cell_alive_color = foreground_color; 
const cell_dead_color = background_color; 

const CellState = enum {
    dead,
    alive
};


const state = struct {
    var pass_action: sg.PassAction = .{};
    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var pixel_buffer = std.mem.zeroes([window_width * window_height]u32);
    var cells: [num_cells_x * num_cells_y]CellState = undefined; 
};


export fn init() void {
    sg.setup(.{ 
        .environment = sglue.environment(), 
        .logger = .{ .func = slog.func } 
    });


    // Vertex Buffer
    const vertices = [_]f32 {
        // positions    // uvs
        -1.0,  1.0, 0.0, 0.0, 0.0,
        1.0,   1.0, 0.0, 1.0, 0.0,
        1.0,  -1.0, 0.0, 1.0, 1.0,
        -1.0, -1.0, 0.0, 0.0, 1.0,
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&vertices)
    });

    // Index Buffer
    const indices = [_]u16 { 0, 1, 2, 0, 2, 3 };
    state.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&indices)
    });

    // Image which can be dynamically updated
    const image = sg.makeImage(.{
        .width = window_width,
        .height = window_height,
        .pixel_format = .RGBA8,
        .sample_count = 1,
        .usage = .STREAM
    });
    state.bind.images[shd.IMG_tex] = image;

    // Sampler object
    const sampler = sg.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE
    });
    state.bind.samplers[shd.SMP_smp] = sampler;

    // Shader and Pipeline object
    var pip_desc: sg.PipelineDesc = .{
        .shader = sg.makeShader(shd.quadShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
    };

    pip_desc.layout.attrs[shd.ATTR_quad_position] = .{ .format = .FLOAT3 };
    pip_desc.layout.attrs[shd.ATTR_quad_texcoord0] = .{ .format = .FLOAT2 };

    state.pip = sg.makePipeline(pip_desc);

    // Default Pass Action
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1}
    };

    // Set initial cell state
    @memset(&state.cells, .dead);

    state.cells[0] = .alive;
}

fn makeColorRGBA8(color: u32) u32 {
    switch (native_endian) {
        .little => {
            const red: u8 = @truncate(color >> 24);
            const green: u8 = @truncate(color >> 16);
            const blue: u8 = @truncate(color >> 8);
            const alpha: u8 = @truncate(color);
            const new_color: u32 = @as(u32, alpha) << 24 | @as(u32, blue) << 16 | @as(u32, green) << 8 | @as(u32, red);
            return new_color;
        },
        else  => {
            return color;
        }
    }
}

inline fn drawPixel(x: usize, y: usize, color: u32) void {
    const outOfBounds = x < 0 or x > window_width or y < 0 or y > window_height;
    if (!outOfBounds) {
        state.pixel_buffer[(y * window_width) + x] = color;
    }
}


fn clearColorBuffer(color: u32) void {
    @memset(&state.pixel_buffer, color);
}

fn drawRectangle(x: usize, y: usize, w: usize, h: usize, color: u32) void {
    for (0..h) |i| {
        for (0..w) |j| {
            const curr_x = j + x;
            const curr_y = i + y;
            drawPixel(curr_x, curr_y, color);
        }
    }
}

fn drawCellStates() void {
    for (0.., state.cells) |i, cell_state| {
        // Convert index to x and y position
        const x = i % num_cells_x;
        const y = i / num_cells_x;

        const color = switch(cell_state) {
            .dead => cell_dead_color,
            .alive => cell_alive_color
        };
        drawRectangle(x * cell_size, y * cell_size, cell_size, cell_size, color);
    }
}

export fn frame() void {
    clearColorBuffer(background_color);
    drawCellStates();

    var image_data: sg.ImageData = .{};
    image_data.subimage[0][0] = sg.asRange(&state.pixel_buffer);
    sg.updateImage(state.bind.images[shd.IMG_tex], image_data);
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.draw(0, 6, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{ 
        .init_cb = init, 
        .frame_cb = frame, 
        .cleanup_cb = cleanup, 
        .width = window_width, 
        .height = window_height, 
        .icon = .{ .sokol_default = true }, 
        .window_title = "Zig Game of Life", 
        .logger = .{ .func = slog.func }, 
        .win32_console_attach = true 
    });
}
