package platform

import "core:dynlib"
import "core:os"
import "core:c/libc"
import "base:runtime"
import "core:fmt"
import "core:mem"
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

	input : [Game_Input_Index]Game_Input,
	sdl_pending_key_events : [dynamic]SDL.Event,

	game_memory : Game_Memory,

	backbuffer : Game_Offscreen_Buffer,

	frame_start : u64,

	game_api : Game_API,
}
state : SDL_Handmade_State

SDL_Audio_Output_Buffer :: struct {
	stream : ^SDL.AudioStream,
	current_sine_sample : int, // simple srunning counter .. maybe we should deprecate

	channel_num : i32, // MONO=1, STEREO=2 etc
	sample_rate : i32, // e.g 8000Hz
	format : SDL.AudioFormat, // maybe we should just support F32 or S16 by default..
}

// Will delete previous offscreen buffer and allocate a new one for us
SDL_resize_offscreen_buffer :: proc(buffer : ^Game_Offscreen_Buffer, new_dim : [2]u32) {
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
SDL_display_buffer_to_window :: proc(window : ^SDL.Window, buffer : ^Game_Offscreen_Buffer) {
	surface := SDL.GetWindowSurface(state.window);
	if surface != nil{
		intrinsics.mem_copy(
			surface.pixels,
			&state.backbuffer.bitmap_memory[0],
			len(state.backbuffer.bitmap_memory)
		)
	}
}

SDL_process_keyboard_msg :: proc(new_state : ^Game_Button_State, is_down : bool) {
	// FIXME: why does this assert trigger? maybe because processing happens in eventrather than iter?
	//assert(new_state.ended_down != is_down)
	//new_state.ended_down = is_down
	new_state.ended_down = is_down
	new_state.half_transition_count+=1
}
SDL_process_gamepad_msg :: proc(old_state : ^Game_Button_State, new_state : ^Game_Button_State, is_down : bool) {
	new_state.ended_down = is_down
	new_state.half_transition_count = new_state.ended_down != old_state.ended_down ? 1 : 0
}
SDL_load_game_api :: proc() -> (Game_API, bool) {
	dll_time, dll_time_err := os.last_write_time_by_name("game.dll")
	if dll_time_err != os.ERROR_NONE {
		fmt.println("Could not fetch last write date of game.dll")
		return {}, false
	}
	dll_name := fmt.tprintf("game_copy.dll")
	copy_cmd := fmt.ctprintf("copy game.dll {0}", dll_name)
	if libc.system(copy_cmd) != 0 {
		fmt.println("Failed to copy game.dll to {0}", dll_name)
		return {}, false
	}
	lib, lib_ok := dynlib.load_library(dll_name)
	if !lib_ok {
		fmt.println("Failed loading game DLL")
		return {}, false
	}
	api := Game_API {
		game_update_and_render = cast(proc(memory : ^Game_Memory, input : ^Game_Input, buffer : ^Game_Offscreen_Buffer, audio_out : ^Game_Audio_Output_Buffer))(dynlib.symbol_address(lib, "game_update_and_render") or_else nil),
	}
	if api.game_update_and_render == nil {
		dynlib.unload_library(api.lib)
		fmt.println("Game DLL missing required procedure")
		return {}, false
	}

	return api, true
}
SDL_unload_game_api :: proc(api : Game_API) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}
}

main :: proc() {
	init := proc "c" (appstate: ^rawptr, argc: c.int, argv: [^]cstring) -> SDL.AppResult {
		context = runtime.default_context()

		ok : bool
		state.game_api,ok = SDL_load_game_api()
		assert(ok)

		// Initialize all SDL subsystems
		if !SDL.Init(SDL.INIT_VIDEO | SDL.INIT_GAMEPAD | SDL.INIT_AUDIO) {
			SDL.Log("SDL Initialization Failed!")
			return SDL.AppResult.FAILURE;
		}
		// Create a window
		state.window = SDL.CreateWindow("Handmade Hero", 768, 512, flags = {.RESIZABLE})
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

		// Initialize the Game's memory (we will pass it though to game layer)
		state.game_memory.permanent_storage,_ = mem.alloc(mem.Megabyte*64)
		state.game_memory.transient_storage,_ = mem.alloc(mem.Gigabyte*1)

		// Test out our wav functionality
		//wav_test()

		state.frame_start = SDL.GetPerformanceCounter()
		return SDL.AppResult.CONTINUE
	}

	iter := proc "c" (appstate: rawptr) -> SDL.AppResult  {
		context = runtime.default_context()
		frame_start := state.frame_start

		// reset transient storage per-frame
		state.game_memory.transient_storage_size = 0

		// Do Input stuff
		new_input := &state.input[.NEW]
		old_input := &state.input[.OLD]

		// migrate the previous key states for keyboard
		KEYBOARD_CIDX :: 0
		mem.zero_item(&new_input.controllers[KEYBOARD_CIDX])
		for button, bidx in old_input.controllers[KEYBOARD_CIDX].buttons {
			new_input.controllers[KEYBOARD_CIDX].buttons[auto_cast bidx].ended_down = button.ended_down
		}

		//assert(!new_input.controllers[0].buttons[.MOVE_UP].ended_down)

		// Update all controllers based on SDL gamepads
		gamepad_count : i32
		gamepads : [^]SDL.JoystickID = SDL.GetGamepads(&gamepad_count);
		for gamepad_idx in 0..<gamepad_count {
			cidx := gamepad_idx + 1 // because cidx=0 is our keyboard for now
			gamepad :^SDL.Gamepad = SDL.OpenGamepad(gamepads[gamepad_idx]);

			left_x := f32(SDL.GetGamepadAxis(gamepad, .LEFTX))/f32(max(i16));
			right_x := f32(SDL.GetGamepadAxis(gamepad, .RIGHTX))/f32(max(i16));
			avg_x := left_x + right_x
			new_input.controllers[cidx].stick_x = avg_x


			right_y := f32(SDL.GetGamepadAxis(gamepad, .RIGHTY))/f32(max(i16))
			left_y := f32(SDL.GetGamepadAxis(gamepad, .LEFTY))/f32(max(i16))
			avg_y := left_y + right_y
			new_input.controllers[cidx].stick_y = avg_y

			l_shoulder := SDL.GetGamepadButton(gamepad, .LEFT_SHOULDER)
			r_shoulder := SDL.GetGamepadButton(gamepad, .RIGHT_SHOULDER)
			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.L_SHOULDER], &new_input.controllers[cidx].buttons[.L_SHOULDER], l_shoulder)
			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.R_SHOULDER], &new_input.controllers[cidx].buttons[.R_SHOULDER], r_shoulder)

			dpad_up    := SDL.GetGamepadButton(gamepad, .DPAD_UP)
			dpad_down  := SDL.GetGamepadButton(gamepad, .DPAD_DOWN)
			dpad_right := SDL.GetGamepadButton(gamepad, .DPAD_RIGHT)
			dpad_left  := SDL.GetGamepadButton(gamepad, .DPAD_LEFT)

			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.MOVE_UP], &new_input.controllers[cidx].buttons[.MOVE_UP], dpad_up)
			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.MOVE_DOWN], &new_input.controllers[cidx].buttons[.MOVE_DOWN], dpad_down)
			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.MOVE_RIGHT], &new_input.controllers[cidx].buttons[.MOVE_RIGHT], dpad_right)
			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.MOVE_LEFT], &new_input.controllers[cidx].buttons[.MOVE_LEFT], dpad_left)

			action_up := SDL.GetGamepadButton(gamepad, .NORTH)
			action_down := SDL.GetGamepadButton(gamepad, .SOUTH)
			action_left := SDL.GetGamepadButton(gamepad, .WEST)
			action_right := SDL.GetGamepadButton(gamepad, .EAST)

			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.ACTION_UP], &new_input.controllers[cidx].buttons[.ACTION_UP], action_up)
			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.ACTION_DOWN], &new_input.controllers[cidx].buttons[.ACTION_DOWN], action_down)
			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.ACTION_RIGHT], &new_input.controllers[cidx].buttons[.ACTION_RIGHT], action_right)
			SDL_process_gamepad_msg(&old_input.controllers[cidx].buttons[.ACTION_LEFT], &new_input.controllers[cidx].buttons[.ACTION_LEFT], action_left)
		}

		// Update based on key events
		// Right now we are hijacking the events from event callback
		for event in state.sdl_pending_key_events {
			kevent : SDL.KeyboardEvent = event.key
			is_down := kevent.down
			if kevent.key == SDL.K_ESCAPE {
				return SDL.AppResult.SUCCESS
            } else if kevent.key == SDL.K_SPACE {
				return SDL.AppResult.SUCCESS
			}
			else if kevent.key == SDL.K_W { SDL_process_keyboard_msg(&new_input.controllers[0].buttons[.MOVE_UP], is_down) }
			else if kevent.key == SDL.K_S { SDL_process_keyboard_msg(&new_input.controllers[0].buttons[.MOVE_DOWN], is_down) }
			else if kevent.key == SDL.K_A { SDL_process_keyboard_msg(&new_input.controllers[0].buttons[.MOVE_LEFT], is_down) }
			else if kevent.key == SDL.K_D { SDL_process_keyboard_msg(&new_input.controllers[0].buttons[.MOVE_RIGHT], is_down) }
			else if kevent.key == SDL.K_Q { SDL_process_keyboard_msg(&new_input.controllers[0].buttons[.L_SHOULDER], is_down) }
			else if kevent.key == SDL.K_E { SDL_process_keyboard_msg(&new_input.controllers[0].buttons[.R_SHOULDER], is_down) }
		}
		clear(&state.sdl_pending_key_events)

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
			// TODO: Also this should be a temp alloc
			game_audio_out.samples_to_write = make([]f32, 512)
		}

		// call update_and_render from platform agnostic code!
		state.game_api.game_update_and_render(&state.game_memory, new_input, &state.backbuffer, &game_audio_out)

		// test
		if new_input.controllers[0].buttons[.MOVE_UP].ended_down {
			sdl_visualize_last_audio_samples(&state.backbuffer,400)
		}

		SDL_display_buffer_to_window(state.window, &state.backbuffer)

		SDL.RenderPresent(state.renderer)
		state.audio_out.current_sine_sample = game_audio_out.current_sine_sample

		if queued_samples_count < i32(minimum_audio) {
			// to avoid floating point rounding errors
			state.audio_out.current_sine_sample %= int(state.audio_out.sample_rate);
			SDL.PutAudioStreamData(state.audio_out.stream, &game_audio_out.samples_to_write[0], auto_cast len(game_audio_out.samples_to_write) * size_of(f32));
		}


		// Timing
		frame_end := SDL.GetPerformanceCounter()
		count := frame_end - frame_start
		freq := SDL.GetPerformanceFrequency()

		seconds_elapsed_for_frame := (f64(count) / f64(freq))

		target_fps := 60.0
		target_seconds_per_frame := 1.0 / target_fps

		if seconds_elapsed_for_frame < target_seconds_per_frame {
			sleep_sec := target_seconds_per_frame - seconds_elapsed_for_frame
			SDL.DelayPrecise(u64(sleep_sec * 1000 * 1000 * 1000)); // sec -> nsec
			frame_end = SDL.GetPerformanceCounter()
			count = frame_end - frame_start
			seconds_elapsed_for_frame = (f64(count) / f64(freq))
		}
		// reset frame_start for next frame
		state.frame_start = frame_end

		fps := (f64(freq) / f64(count))
		fmt.printf("ms: %.2f - fps: %.2f\n", 1000*seconds_elapsed_for_frame, fps)

		// Copy back our processed input to old input for next frame processing
		temp := state.input[.OLD]
		state.input[.OLD] = state.input[.NEW]
		state.input[.NEW] = temp

		return SDL.AppResult.CONTINUE;
	}
	events := proc "c" (appstate: rawptr, event: ^SDL.Event) -> SDL.AppResult {
		context = runtime.default_context()

		new_input := &state.input[.NEW]

		if event.type == SDL.EventType.QUIT {
			return SDL.AppResult.SUCCESS;
		} else if event.type == SDL.EventType.WINDOW_RESIZED {
			// Resize our backbuffer with new window dimensions
			w,h : i32
			SDL.GetWindowSize(state.window, &w, &h)
			SDL_resize_offscreen_buffer(&state.backbuffer, {u32(w), u32(h)})
		} else if event.type == SDL.EventType.KEY_DOWN || event.type == SDL.EventType.KEY_UP {
			// pass the key event to our internal structure, to update in next _Iterate
			append(&state.sdl_pending_key_events, event^)
		}

		return SDL.AppResult.CONTINUE;
	}

	quit := proc "c" (appstate: rawptr, r: SDL.AppResult) {
		context = runtime.default_context()
		fmt.println("quit")
	}

	SDL.EnterAppMainCallbacks(0, nil, init, iter, events, quit)
}

platform_read_entire_file :: proc(filename : cstring) -> []u8 {
	size : uint
	ptr :[^]u8= auto_cast SDL.LoadFile(filename, &size);
	return ptr[:size]
}

platform_write_entire_file :: proc(filename : cstring, data : []u8) -> (ok : bool) {
	if SDL.SaveFile(filename, &data[0], len(data)) {
		ok = true
	}
	return ok
}

render_vertical_line_from_0 :: proc(backbuffer : ^Game_Offscreen_Buffer, target_y : i32, offset_x : i32, line_width : i32, color : u32) {
	if target_y > 0 {
		for y in 0..<target_y {
			y_coord := i32(backbuffer.dim[1]/2) - y
			for x in 0..<line_width {
				x_coord := offset_x + x
				pitch_in_u32 := backbuffer.dim[0]
				backbuffer.bitmap_memory[u32(y_coord) * pitch_in_u32 + u32(x_coord)] = color;
			}
		}
	} else {
		for y in target_y..<0 {
			y_coord := i32(backbuffer.dim[1]/2) - y
			for x in 0..<line_width {
				x_coord := offset_x + x
				pitch_in_u32 := backbuffer.dim[0]
				backbuffer.bitmap_memory[u32(y_coord) * pitch_in_u32 + u32(x_coord)] = color;
			}
		}
	}
}

sdl_visualize_last_audio_samples :: proc(backbuffer : ^Game_Offscreen_Buffer, sample_count : u32) {
	window_w := backbuffer.dim[0]
	width_per_line := f32(window_w)/ f32(sample_count)
	assert(width_per_line > 0)

	total_samples := state.audio_out.channel_num * i32(sample_count)
	// TODO: this should become a temp allocation!
	data := make([]f32, total_samples)
	defer delete(data)

	SDL.GetAudioStreamData(state.audio_out.stream, auto_cast &data[0], total_samples * size_of(f32))
	for sample_idx in 0..<sample_count {
		offset_x := width_per_line * f32(sample_idx)
		// FIXME: We just output the Left or MONO channel for now
		target_y := data[sample_idx * u32(state.audio_out.channel_num)] * f32(backbuffer.dim[1])/2
		render_vertical_line_from_0(backbuffer, i32(target_y), i32(offset_x), i32(width_per_line), 0xffffffff)
	}
}