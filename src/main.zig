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
const cell_size: u32 = 16;
const num_cells_x: usize = window_width / cell_size;
const num_cells_y: usize = window_height / cell_size;
const num_cells = num_cells_x * num_cells_y;

const background_color = makeColorRGBA8(0x96a6c8ff);
const foreground_color = makeColorRGBA8(0x181818ff);
const cell_alive_color = foreground_color; 
const cell_dead_color = background_color; 

const CellState = enum {
    dead,
    alive
};

const GameState = enum {
    drawing,
    running
};


const state = struct {
    var pass_action: sg.PassAction = .{};
    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var pixel_buffer = std.mem.zeroes([window_width * window_height]u32);
    var cells: [num_cells]CellState = undefined; 
    var event_type: sapp.EventType = undefined;
    var drawing_index: isize = -1;
    var game_state: GameState = .drawing;
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

fn getLivingNeighbours(x: isize) usize {
    // [ ][ ][ ]
    // ^top_row_start
    // [ ][ ][ ]
    // ^middle_row_start
    // [ ][ ][ ]
    // ^bottom_row_start

    const top_row_start: isize = @intCast(x - num_cells_x - 1);
    const middle_row_start: isize = @intCast(x - 1);
    const bottom_row_start: isize = @intCast(x + num_cells_x - 1);
    var num_living_neighbours: usize = 0;

    // Check top row
    for (0..3) |i| {
        const index: isize = top_row_start + @as(isize, @intCast(i));
        const skip = index < 0 or index >= num_cells or index == x;
        if (skip) {
            continue;
        }
        const cell_state = state.cells[@intCast(index)];
        if (cell_state == .alive) {
            num_living_neighbours += 1;
        }
    }
    // Check middle row
    for (0..3) |i| {
        const index: isize = middle_row_start + @as(isize, @intCast(i));
        const skip = index < 0 or index >= num_cells or index == x;
        if (skip) {
            continue;
        }
        const cell_state = state.cells[@intCast(index)];
        if (cell_state == .alive) {
            num_living_neighbours += 1;
        }
    }
    // Check bottom row
    for (0..3) |i| {
        const index: isize = bottom_row_start + @as(isize, @intCast(i));
        const skip = index < 0 or index >= num_cells or index == x;
        if (skip) {
            continue;
        }
        const cell_state = state.cells[@intCast(index)];
        if (cell_state == .alive) {
            num_living_neighbours += 1;
        }
    }
    return num_living_neighbours;
}

fn drawGrid() void {
    for (0..window_height) |y| {
        for (0..window_width) |x| {
            if (x % cell_size == 0 or y % cell_size == 0) {
                drawPixel(x, y, foreground_color);
            }
        }
    }
}

fn applyCellStateRules(cells: [num_cells]CellState) [num_cells]CellState {
    var new_cells: [num_cells]CellState = undefined;
    @memset(&new_cells, .dead);
    for (0.., cells) |index, cell_state| {
        var new_cell_state: CellState = cell_state;
        const num_living_neighbours = getLivingNeighbours(@intCast(index));
        if (cell_state == .alive) {
            // 1: Any live cell with fewer than two living neighbours dies
            if (num_living_neighbours < 2) {
                new_cell_state = .dead;
            } else if (num_living_neighbours == 2 or num_living_neighbours == 3) {
                // 2: Any live cell with two or three live neighbours lives.
                new_cell_state = .alive;
            } else {
                // 3: Any live cell with more then three live neighbours dies
                new_cell_state = .dead;
            }
        } else {
            // 4: Any dead cell with exactly three live neighbours becomes alive
            if (num_living_neighbours == 3) {
                new_cell_state = .alive;
            }
        }
        new_cells[index] = new_cell_state;
    }
    return new_cells;
}

export fn event(eptr: [*c]const sapp.Event) void {
    const e: *const sapp.Event = @ptrCast(eptr);
    state.event_type = e.type;
    if (state.event_type == .KEY_UP and e.key_code == .D) {
        if (state.game_state == .running) {
            state.game_state = .drawing;
        }
        else {
            state.game_state = .running;
        }
    }

    const mouse_x: isize = @intFromFloat(e.mouse_x);
    const mouse_y: isize = @intFromFloat(e.mouse_y);
    const cell_x: isize = @divFloor(mouse_x, cell_size);
    const cell_y: isize  = @divFloor(mouse_y, cell_size);
    const outOfBounds = cell_x < 0 or cell_x >= num_cells_x or cell_y < 0 or cell_y >= num_cells_y;
    if (outOfBounds) {
        state.drawing_index = -1;
    } else {
        state.drawing_index = (cell_y * num_cells_x) + cell_x;
    }
}

export fn frame() void {
    clearColorBuffer(background_color);


    if (state.game_state == .drawing) {
        if (state.event_type == .MOUSE_DOWN and state.drawing_index != -1) {
            state.cells[@intCast(state.drawing_index)] = .alive;

        }
    } else {
        state.cells = applyCellStateRules(state.cells);

    }

    drawCellStates();
    drawGrid();

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
        .event_cb = event,
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
