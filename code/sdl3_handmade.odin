package main
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:c"

import SDL "vendor:sdl3"

// TODO: can we query a specific pixel format for our surface? It would be pretty neat.
SDL_Handmade_State :: struct {
	window : ^SDL.Window,
	renderer : ^SDL.Renderer,
	resize_count : u32,

	offset_x : i32,
	offset_y : i32,

	bitmap_memory : []u32,
}
state : SDL_Handmade_State

main :: proc() {
	init := proc "c" (appstate: ^rawptr, argc: c.int, argv: [^]cstring) -> SDL.AppResult {
		if !SDL.Init(SDL.INIT_VIDEO) {
			SDL.Log("SDL Initialization Failed!")
			return SDL.AppResult.FAILURE;
		}
		state.window = SDL.CreateWindow("Handmade Hero", 640, 480, flags = {.RESIZABLE})
		if state.window == nil {
			SDL.Log("Window creation Failed!")
			return SDL.AppResult.FAILURE
		}
		state.renderer = SDL.CreateRenderer(state.window, "software")
		if state.renderer == nil {
			SDL.Log("Renderer creation Failed!")
			return SDL.AppResult.FAILURE
		}
		SDL.SetRenderVSync(state.renderer, 1);

		surface := SDL.GetWindowSurface(state.window);
		if surface != nil {
			state.bitmap_memory = ([^]u32)(surface.pixels)[:surface.w*surface.h]
		}

		return SDL.AppResult.CONTINUE
	}

	iter := proc "c" (appstate: rawptr) -> SDL.AppResult  {
		context = runtime.default_context()

		state.offset_x+=1

		// Clear the surface pixels to RED
		surface := SDL.GetWindowSurface(state.window);
		if surface != nil {
			pixel_format_details := SDL.GetPixelFormatDetails(surface.format)
			SDL.FillSurfaceRect(surface, nil, SDL.MapRGB(pixel_format_details, nil, 0, 0, 0))

			// Draw a simple pattern directly to surface's backbuffer
			for y in 0..<surface.h {
				for x in 0..<surface.w {
					color := SDL.MapRGB(pixel_format_details, nil, 0, u8(x + state.offset_x), u8(y + state.offset_y))
					state.bitmap_memory[i32(y) * (surface.pitch / size_of(u32)) + i32(x)] = color;
				}
			}

			// TODO: Can't we just update the surface? not the window
			SDL.RenderPresent(state.renderer)
		}

		return SDL.AppResult.CONTINUE;
	}
	events := proc "c" (appstate: rawptr, event: ^SDL.Event) -> SDL.AppResult {
		if event.type == SDL.EventType.QUIT {
			return SDL.AppResult.SUCCESS;
		} else if event.type == SDL.EventType.WINDOW_RESIZED {
			surface := SDL.GetWindowSurface(state.window);
			if surface != nil {
				state.bitmap_memory = ([^]u32)(surface.pixels)[:surface.w*surface.h]
			}
			state.resize_count += 1
		}

		return SDL.AppResult.CONTINUE;
	}

	quit := proc "c" (appstate: rawptr, r: SDL.AppResult) {
		context = runtime.default_context()
		fmt.println("quit")
	}

	SDL.EnterAppMainCallbacks(0, nil, init, iter, events, quit)
}

