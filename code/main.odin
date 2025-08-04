package main
import "core:fmt"
import "core:time"

import SDL "vendor:sdl3"

main :: proc() {
	WINDOW_WIDTH  :: 1200
	WINDOW_HEIGHT :: 600

	sdl_ok := SDL.Init({.VIDEO})
    assert(sdl_ok)
	defer SDL.Quit()

	window := SDL.CreateWindow("Handmade Hero", WINDOW_WIDTH, WINDOW_HEIGHT, {.OPENGL})
	if window == nil { fmt.eprintln("Failed to create window"); return }
	defer SDL.DestroyWindow(window)

	start_tick := time.tick_now()

	loop: for {
		free_all(context.temp_allocator)
		duration := time.tick_since(start_tick)
		t := f32(time.duration_seconds(duration))

		event: SDL.Event
		for SDL.PollEvent(&event) {
			#partial switch event.type {
			case .KEY_DOWN: #partial switch event.key.scancode { case .ESCAPE: break loop }
			case .QUIT: break loop
			}
		}

		SDL.GL_SwapWindow(window)
	}
}

