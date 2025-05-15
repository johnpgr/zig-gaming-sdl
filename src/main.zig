const std = @import("std");

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
    @cInclude("SDL3_image/SDL_image.h");
});

const NAME = "unnamed_game";
const WIDTH = 800;
const HEIGHT = 600;
const TARGET_FPS = 60;
const TARGET_FRAME_TIME_MS = 1000 / TARGET_FPS;
const MOVE_SPEED = 5.0;

var global_running: bool = true;
var global_paused: bool = false;

pub const Player = struct {
    x: f32,
    y: f32,
    color: c.SDL_Color,
    moving: struct {
        up: bool,
        down: bool,
        left: bool,
        right: bool,
    },

    pub fn init(allocator: std.mem.Allocator, x: f32, y: f32, color: c.SDL_Color) !*Player {
        const self = try allocator.create(Player);
        self.*.x = x;
        self.*.y = y;
        self.*.color = color;
        self.*.moving = .{
            .up = false,
            .down = false,
            .left = false,
            .right = false,
        };

        return self;
    }

    pub fn deinit(self: *Player, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    pub fn process_input(self: *Player, keycode: c.SDL_Keycode, is_down: bool) void {
        switch (keycode) {
            c.SDLK_UP, c.SDLK_W => {
                self.moving.up = is_down;
            },
            c.SDLK_DOWN, c.SDLK_S => {
                self.moving.down = is_down;
            },
            c.SDLK_LEFT, c.SDLK_A => {
                self.moving.left = is_down;
            },
            c.SDLK_RIGHT, c.SDLK_D => {
                self.moving.right = is_down;
            },
            else => {},
        }
    }

    pub fn update_position(self: *Player) void {
        if (self.moving.up) {
            self.y -= MOVE_SPEED;
        }
        if (self.moving.down) {
            self.y += MOVE_SPEED;
        }
        if (self.moving.left) {
            self.x -= MOVE_SPEED;
        }
        if (self.moving.right) {
            self.x += MOVE_SPEED;
        }
    }
};

pub const State = struct {
    player: *Player,

    pub fn init(allocator: std.mem.Allocator, player: *Player) !*State {
        const self = try allocator.create(State);
        self.*.player = player;

        return self;
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.player.deinit(allocator);
        allocator.destroy(self);
    }
};

pub const Game = struct {
    allocator: std.mem.Allocator,
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    state: *State,
    font: *c.TTF_Font,
    last_elapsed_ms: u64,

    pub fn init(allocator: std.mem.Allocator) !Game {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO)) {
            return error.SDL_Init_Failed;
        }
        if (!c.TTF_Init()) {
            return error.TTF_Init_Failed;
        }
        const font = (c.TTF_OpenFont("assets/RetroGaming.ttf", 24) orelse {
            const err = c.SDL_GetError();
            c.SDL_LogError(c.SDL_LOG_CATEGORY_APPLICATION, "TTF_OpenFont failed: %s", err);
            return error.FontLoadError;
        });

        const window: *c.SDL_Window, const renderer: *c.SDL_Renderer = create_window_and_renderer: {
            var window: ?*c.SDL_Window = null;
            var renderer: ?*c.SDL_Renderer = null;
            if (!c.SDL_CreateWindowAndRenderer(
                "Zigmade hero",
                WIDTH,
                HEIGHT,
                c.SDL_WINDOW_RESIZABLE,
                &window,
                &renderer,
            )) {
                c.SDL_LogError(c.SDL_LOG_CATEGORY_APPLICATION, "Could not create window and renderer");
                return error.SDL_CreateWindowAndRenderer_Failed;
            }

            break :create_window_and_renderer .{ window.?, renderer.? };
        };

        const gpu_device = (c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse {
            const err = c.SDL_GetError();
            c.SDL_LogError(c.SDL_LOG_CATEGORY_APPLICATION, "SDL_CreateGPUDevice failed: %s", err);
            return error.GPU_Device_Error;
        });
        c.SDL_LogInfo(c.SDL_LOG_CATEGORY_APPLICATION, "GPU device created: %s", c.SDL_GetGPUDeviceDriver(gpu_device));

        const main_player = try Player.init(allocator, 200, 200, .{
            .r = 255,
            .g = 0,
            .b = 0,
            .a = 255,
        });

        const state = try State.init(allocator, main_player);

        return .{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .state = state,
            .font = font,
            .last_elapsed_ms = 0,
        };
    }

    pub fn deinit(self: *Game) void {
        self.state.deinit(self.allocator);
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
        c.TTF_CloseFont(self.font);
        c.TTF_Quit();
        c.SDL_Quit();
    }

    pub fn handleEvent(self: *Game, event: *c.SDL_Event) void {
        while (c.SDL_PollEvent(event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    global_running = false;
                },
                c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                    const key_event = event.*.key;
                    const key_code = key_event.key;
                    const is_down = key_event.down;
                    const is_repeat = key_event.repeat;

                    if (is_repeat) {
                        continue;
                    }

                    self.state.player.process_input(key_code, is_down);
                    if (key_code == c.SDLK_Q) {
                        global_running = false;
                    }
                },
                c.SDL_EVENT_WINDOW_RESIZED => {},
                else => {},
            }
        }
    }

    pub fn update(self: *Game) void {
        self.state.player.update_position();
    }

    fn render_player(self: *Game) void {
        const rect: c.SDL_FRect = .{
            .h = 100.0,
            .w = 100.0,
            .x = self.state.player.x,
            .y = self.state.player.y,
        };
        _ = c.SDL_SetRenderDrawColor(
            self.renderer,
            self.state.player.color.r,
            self.state.player.color.g,
            self.state.player.color.b,
            self.state.player.color.a,
        );
        _ = c.SDL_RenderFillRect(self.renderer, &rect);
    }

    fn render_text(self: *Game, text: []const u8, x: f32, y: f32, color: c.SDL_Color) !void {
        const text_surface = c.TTF_RenderText_Solid(self.font, text.ptr, text.len, color);
        if (text_surface == null) {
            c.SDL_LogError(c.SDL_LOG_CATEGORY_APPLICATION, "TTF_RenderText_Solid failed: %s", c.SDL_GetError());
            return;
        }

        defer c.SDL_DestroySurface(text_surface);
        const text_texture = c.SDL_CreateTextureFromSurface(self.renderer, text_surface);
        if (text_texture == null) {
            c.SDL_LogError(c.SDL_LOG_CATEGORY_APPLICATION, "SDL_CreateTextureFromSurface failed: %s", c.SDL_GetError());
            return;
        }
        defer c.SDL_DestroyTexture(text_texture);

        var texture_w: f32 = 0;
        var texture_h: f32 = 0;
        if (!c.SDL_GetTextureSize(text_texture, &texture_w, &texture_h)) {
            c.SDL_LogError(c.SDL_LOG_CATEGORY_APPLICATION, "SDL_GetTextureSize failed: %s", c.SDL_GetError());
            return;
        }

        const text_rect = c.SDL_FRect{
            .x = x,
            .y = y,
            .w = texture_w,
            .h = texture_h,
        };
        _ = c.SDL_RenderTexture(self.renderer, text_texture, null, &text_rect);
    }

    fn render_fps_text(self: *Game) !void {
        const fps_value: f32 =
            if (self.last_elapsed_ms == TARGET_FRAME_TIME_MS and 1000 % TARGET_FPS != 0)
                @as(f32, @floatFromInt(TARGET_FPS))
            else if (self.last_elapsed_ms > 0)
                1000.0 / @as(f32, @floatFromInt(self.last_elapsed_ms))
            else
                0.0;
        var fps_text_buffer: [64]u8 = undefined;
        const fps_text_slice = try std.fmt.bufPrintZ(&fps_text_buffer, "FPS: {d:.0}", .{fps_value});
        const text_color = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
        try self.render_text(fps_text_slice, 10.0, 10.0, text_color);
    }

    pub fn render(self: *Game) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255);
        _ = c.SDL_RenderClear(self.renderer);
        self.render_fps_text() catch {
            c.SDL_LogError(c.SDL_LOG_CATEGORY_APPLICATION, "Failed to render FPS text");
        };
        self.render_player();
        _ = c.SDL_RenderPresent(self.renderer);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var game = try Game.init(allocator);
    defer game.deinit();

    while (global_running) {
        const frame_start_time = c.SDL_GetTicks();

        var event: c.SDL_Event = undefined;
        game.handleEvent(&event);

        if (global_paused) {
            continue;
        }

        game.update();
        game.render();

        const frame_end_time = c.SDL_GetTicks();
        const elapsed_ms = frame_end_time - frame_start_time;
        var effective_frame_duration_ms: u64 = 0;
        if (elapsed_ms < TARGET_FRAME_TIME_MS) {
            c.SDL_Delay(@truncate(TARGET_FRAME_TIME_MS - elapsed_ms));
            effective_frame_duration_ms = TARGET_FRAME_TIME_MS;
        } else {
            effective_frame_duration_ms = elapsed_ms;
        }
        game.last_elapsed_ms = effective_frame_duration_ms;
    }
}
