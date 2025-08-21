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

	audio_out : SDL_Audio_Output_Buffer,

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

SDL_Audio_Output_Buffer :: struct {
	stream : ^SDL.AudioStream,
	current_sine_sample : int, // simple srunning counter .. maybe we should deprecate

	channel_num : i32, // MONO=1, STEREO=2 etc
	sample_rate : i32, // e.g 8000Hz
	format : SDL.AudioFormat, // maybe we should just support F32 or S16 by default..
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

		audio_out := SDL_Audio_Output_Buffer{
			channel_num = 1,
			sample_rate = 8000,
			format = .F32,
		}
		spec := SDL.AudioSpec{
			channels = audio_out.channel_num,
			format = audio_out.format,
			freq = audio_out.sample_rate,
		}
		audio_out.stream = SDL.OpenAudioDeviceStream(SDL.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, nil, nil)
		if audio_out.stream == nil {
			SDL.Log("Audio stream creation Failed!")
			return SDL.AppResult.FAILURE
		}
		// OpenAudioDeviceStream starts at paused state, we need to start it manually..
		SDL.ResumeAudioStreamDevice(audio_out.stream);
		state.audio_out = audio_out

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

		frame_start := SDL.GetPerformanceCounter()

		// TODO: remove this
		state.offset_x+=1

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
		game_audio_out := Game_Audio_Output_Buffer{
			sample_rate = state.audio_out.sample_rate,
			current_sine_sample = state.audio_out.current_sine_sample,
			channel_num = state.audio_out.channel_num,
			samples_to_write = make([]f32, 0)
		}
		defer delete(game_audio_out.samples_to_write)

		// optionally provide audio samples for the game to fill
		minimum_audio := state.audio_out.sample_rate * size_of(f32) / 2
		// TODO: latency is too big, also we MUST make sure the samples game writes are enough
		queued_samples_count := SDL.GetAudioStreamQueued(state.audio_out.stream)
		if queued_samples_count < i32(minimum_audio) {
			game_audio_out.samples_to_write = make([]f32, 512)
		}

		// call update_and_render from platform agnostic code!
		game_update_and_render(&state.backbuffer, &game_audio_out, state.offset_x, state.offset_y)
		SDL_display_buffer_to_window(state.window, &state.backbuffer)
		SDL.RenderPresent(state.renderer)
		state.audio_out.current_sine_sample = game_audio_out.current_sine_sample

		if queued_samples_count < i32(minimum_audio) {
			// to avoid floating point rounding errors
			state.audio_out.current_sine_sample %= int(state.audio_out.sample_rate);
			SDL.PutAudioStreamData(state.audio_out.stream, &game_audio_out.samples_to_write[0], auto_cast len(game_audio_out.samples_to_write) * size_of(f32));
		}


    // Helper to print timing stuff
    frame_end := SDL.GetPerformanceCounter()
    count := frame_end - frame_start
    freq := SDL.GetPerformanceFrequency()
    ms_per_frame := 1000.0 * (f64(count) / f64(freq))
    fps:= (f64(freq) / f64(count))
    fmt.printf("ms: %.2f - fps: %.2f\n", ms_per_frame, fps)


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


// The abstraction
Game_Offscreen_Buffer :: SDL_Offscreen_Buffer
Game_Audio_Output_Buffer :: struct {
	current_sine_sample : int, // remove dis
	channel_num : i32,
	sample_rate : i32,

	// game should write all these samples
	// they will be updated to underlying osund buffer
	samples_to_write : []f32,
}