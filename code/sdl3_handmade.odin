package handmade

import "base:runtime"
import "core:fmt"
import "base:intrinsics"
import "core:strings"
import "core:time"
import "core:math"
import "core:c"

import SDL "vendor:sdl3"

// TODO: for audio, maybe the callback is better approach https://github.com/libsdl-org/SDL/blob/main/examples/audio/02-simple-playback-callback/simple-playback-callback.c
// TODO: also wavs https://github.com/libsdl-org/SDL/blob/main/examples/audio/03-load-wav/load-wav.c

SDL_Handmade_State :: struct {
	window : ^SDL.Window,
	renderer : ^SDL.Renderer,

	// Audio stuff (will probably change)
	stream : ^SDL.AudioStream,
	current_sine_sample : int,

	offset_x : i32,
	offset_y : i32,

	backbuffer : SDL_Offscreen_Buffer,
}
state : SDL_Handmade_State

Pixel_Format_Info :: struct{
	r_shift : u8,
	g_shift : u8,
	b_shift : u8,
}
SDL_Offscreen_Buffer :: struct {
	px_info : Pixel_Format_Info,
	bitmap_memory : []u32,
	dim : [2]u32,
	bytes_per_pixel : u32,
}

// Will delete previous offscreen buffer and allocate a new one for us
SDL_resize_offscreen_buffer :: proc(buffer : ^SDL_Offscreen_Buffer, new_dim : [2]u32) {
	if len(buffer.bitmap_memory) > 0 {
		delete(buffer.bitmap_memory)
	}

	surface := SDL.GetWindowSurface(state.window);
	if surface != nil {
		pixel_format_details := SDL.GetPixelFormatDetails(surface.format)

		buffer.dim = new_dim
		buffer.bytes_per_pixel = 4
		buffer.bitmap_memory = make([]u32, buffer.dim.x*buffer.dim.y*buffer.bytes_per_pixel)
		buffer.px_info = Pixel_Format_Info{
			r_shift = pixel_format_details.Rshift,
			g_shift = pixel_format_details.Gshift,
			b_shift = pixel_format_details.Bshift,
		}
	}
}

// Will write the contents of our offscreen buffer to the window's surface
SDL_display_buffer_to_window :: proc(window : ^SDL.Window, buffer : ^SDL_Offscreen_Buffer) {
	surface := SDL.GetWindowSurface(state.window);
	if surface != nil{
		intrinsics.mem_copy(
			surface.pixels,
			&state.backbuffer.bitmap_memory[0],
			len(state.backbuffer.bitmap_memory)
		)
	}
}

main :: proc() {
	init := proc "c" (appstate: ^rawptr, argc: c.int, argv: [^]cstring) -> SDL.AppResult {
		context = runtime.default_context()

		// Initialize all SDL subsystems
		if !SDL.Init(SDL.INIT_VIDEO | SDL.INIT_GAMEPAD | SDL.INIT_AUDIO) {
			SDL.Log("SDL Initialization Failed!")
			return SDL.AppResult.FAILURE;
		}
		// Create a window
		state.window = SDL.CreateWindow("Handmade Hero", 640, 480, flags = {.RESIZABLE})
		if state.window == nil {
			SDL.Log("Window creation Failed!")
			return SDL.AppResult.FAILURE
		}
		// Create a renderer
		state.renderer = SDL.CreateRenderer(state.window, "software")
		if state.renderer == nil {
			SDL.Log("Renderer creation Failed!")
			return SDL.AppResult.FAILURE
		}
		SDL.SetRenderVSync(state.renderer, 1)

		// Initialize audio as mono with float32 data, sampling them at 8000Hz
		spec := SDL.AudioSpec{
			channels = 1,
			format = .F32,
			freq = 8000,
		}
		state.stream = SDL.OpenAudioDeviceStream(SDL.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, nil, nil)
		if state.stream == nil {
			SDL.Log("Audio stream creation Failed!")
			return SDL.AppResult.FAILURE
		}
		// OpenAudioDeviceStream starts at paused state, we need to start it manually..
		SDL.ResumeAudioStreamDevice(state.stream);

		// Make our initial backbuffer
		w,h : i32
		SDL.GetWindowSize(state.window, &w, &h)
		SDL_resize_offscreen_buffer(&state.backbuffer, {u32(w), u32(h)})

    // Test out our wav functionality
    //wav_test()

		return SDL.AppResult.CONTINUE
	}

	iter := proc "c" (appstate: rawptr) -> SDL.AppResult  {
		context = runtime.default_context()

		state.offset_x+=1

		// Update with our backbuffer's colors
		for y in 0..<state.backbuffer.dim[1] {
			for x in 0..<state.backbuffer.dim[0] {
				pitch_in_u32 := state.backbuffer.dim[0]
				color :=
					(u32(i32(x)%255+state.offset_x)%255 << state.backbuffer.px_info.g_shift) |
					(u32(i32(y)%255+state.offset_y)%255 << state.backbuffer.px_info.b_shift)
				state.backbuffer.bitmap_memory[u32(y) * pitch_in_u32 + u32(x)] = color;
			}
		}

		SDL_display_buffer_to_window(state.window, &state.backbuffer)
		SDL.RenderPresent(state.renderer)

		// Do gamepad stuff
		//SDL.UpdateGamepads()
		gamepad_count : i32
		gamepads : [^]SDL.JoystickID = SDL.GetGamepads(&gamepad_count);
		for gamepad_idx in 0..<gamepad_count {
			fmt.println("gamepad: ", gamepad_idx)
			gamepad :^SDL.Gamepad = SDL.OpenGamepad(gamepads[gamepad_idx]);

			left_x := SDL.GetGamepadAxis(gamepad, .LEFTX);
			right_x := SDL.GetGamepadAxis(gamepad, .RIGHTX);
			left_y := SDL.GetGamepadAxis(gamepad, .LEFTY);
			right_y := SDL.GetGamepadAxis(gamepad, .RIGHTY);


			state.offset_x += i32(right_x)
			state.offset_x -= i32(left_x)
			state.offset_y += i32(right_y)
			state.offset_y -= i32(left_y)

			dpad_up    := SDL.GetGamepadButton(gamepad, .DPAD_UP);
			dpad_down  := SDL.GetGamepadButton(gamepad, .DPAD_DOWN);
			dpad_right := SDL.GetGamepadButton(gamepad, .DPAD_RIGHT);
			dpad_left  := SDL.GetGamepadButton(gamepad, .DPAD_LEFT);
		}

		// Feed our audio stream if need be
		minimum_audio := 8000 * size_of(f32) / 2
		if SDL.GetAudioStreamQueued(state.stream) < i32(minimum_audio) {
			// Right now we are feeding 512 samples if there is less than half a second queued
			samples : [512] f32
			// We generate a simple 440Hz pure tone?
      volume := f32(0.005)
			for &sample, idx in samples {
				freq := 440
				phase := f32(state.current_sine_sample*freq) / f32(8000)
				sample = SDL.sinf(phase*2*math.PI) * volume
				state.current_sine_sample+=1
			}
			// to avoid floating point rounding errors
			state.current_sine_sample %= 8000;
			SDL.PutAudioStreamData(state.stream, &samples[0], len(samples) * size_of(f32));
		}



		return SDL.AppResult.CONTINUE;
	}
	events := proc "c" (appstate: rawptr, event: ^SDL.Event) -> SDL.AppResult {
		context = runtime.default_context()

		if event.type == SDL.EventType.QUIT {
			return SDL.AppResult.SUCCESS;
		} else if event.type == SDL.EventType.WINDOW_RESIZED {
			// Resize our backbuffer with new window dimensions
			w,h : i32
			SDL.GetWindowSize(state.window, &w, &h)
			SDL_resize_offscreen_buffer(&state.backbuffer, {u32(w), u32(h)})
		} else if event.type == SDL.EventType.KEY_DOWN || event.type == SDL.EventType.KEY_UP {
			kevent : SDL.KeyboardEvent = event.key
			is_down := kevent.down
			if kevent.key == SDL.K_ESCAPE {
				return SDL.AppResult.SUCCESS;
            }
			if is_down {
				if kevent.key == SDL.K_UP do state.offset_y -= 10
				if kevent.key == SDL.K_DOWN do state.offset_y += 10
				if kevent.key == SDL.K_LEFT do state.offset_x -= 10
				if kevent.key == SDL.K_RIGHT do state.offset_x += 10
			}
		}

		return SDL.AppResult.CONTINUE;
	}

	quit := proc "c" (appstate: rawptr, r: SDL.AppResult) {
		context = runtime.default_context()
		fmt.println("quit")
	}

	SDL.EnterAppMainCallbacks(0, nil, init, iter, events, quit)
}

