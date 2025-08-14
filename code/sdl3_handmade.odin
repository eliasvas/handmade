package main
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:c"

import SDL "vendor:sdl3"

Handmade_State :: struct {
	window : ^SDL.Window,
	renderer : ^SDL.Renderer,
	resize_count : u32,
}
state : Handmade_State

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
		return SDL.AppResult.CONTINUE
	}

	iter := proc "c" (appstate: rawptr) -> SDL.AppResult  {
		context = runtime.default_context()


		if state.resize_count % 2 == 0 do SDL.SetRenderDrawColor(state.renderer, 0, 255, 0, 255); else do SDL.SetRenderDrawColor(state.renderer, 255, 0, 0, 255)
		SDL.RenderClear(state.renderer)

		//rect := SDL.FRect{10, 10, 100, 100}
		//SDL.RenderFillRect(state.renderer, &rect)

		SDL.RenderPresent(state.renderer)

		return SDL.AppResult.CONTINUE;
	}
	events := proc "c" (appstate: rawptr, event: ^SDL.Event) -> SDL.AppResult {
		if event.type == SDL.EventType.QUIT {
			return SDL.AppResult.SUCCESS;
		} else if event.type == SDL.EventType.WINDOW_RESIZED {
			state.resize_count += 1
		}

		return SDL.AppResult.CONTINUE;
	}

	quit := proc "c" (appstate: rawptr, r: SDL.AppResult) {}

	SDL.EnterAppMainCallbacks(0, nil, init, iter, events, quit)
}

