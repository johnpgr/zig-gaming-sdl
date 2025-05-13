const std = @import("std");

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
});

const NAME = "unnamed_game";
const WIDTH = 800;
const HEIGHT = 600;

var global_running: bool = true;
var global_paused: bool = false;

pub const Game = struct {
    allocator: std.mem.Allocator,
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,

    pub fn init(allocator: std.mem.Allocator) !Game {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO)) {
            return error.SDL_Init_Failed;
        }

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

        return .{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
        };
    }

    pub fn deinit(self: *Game) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_Quit();
    }

    pub fn handleEvent(_: *Game, event: *c.SDL_Event) void {
        while(c.SDL_PollEvent(event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    global_running = false;
                },
                c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {},
                c.SDL_EVENT_WINDOW_RESIZED => {},
                else => {},
            }
        }

    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var game = try Game.init(allocator);
    defer game.deinit();

    while(global_running) {
        var event: c.SDL_Event = undefined;
        game.handleEvent(&event);
        if (global_paused) {
            continue;
        }
    }
}
