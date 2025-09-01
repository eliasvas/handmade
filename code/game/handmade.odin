package game

import "base:runtime"
import "core:fmt"
import "base:intrinsics"
import "core:strings"
import "core:time"
import "core:math"
import "core:c"

render_weird_gradient :: proc(backbuffer : ^Game_Offscreen_Buffer, offset_x : i32, offset_y : i32) {
	for y in 0..<backbuffer.dim[1] {
		for x in 0..<backbuffer.dim[0] {
			pitch_in_u32 := backbuffer.dim[0]
			color := (u32(i32(x)%255+offset_x)%255 << backbuffer.px_info.g_shift) | (u32(i32(y)%255+offset_y)%255 << backbuffer.px_info.b_shift)
			//color := (u32(i32(x)%255+offset_x)%255 << backbuffer.px_info.r_shift) | (u32(i32(y)%255+offset_y)%255 << backbuffer.px_info.b_shift)
			backbuffer.bitmap_memory[u32(y) * pitch_in_u32 + u32(x)] = color;
		}
	}
}
render_player :: proc(backbuffer : ^Game_Offscreen_Buffer, posx : int, posy : int) {
	//color := u32(0xFFFFFFFF);
	color := u32(0xFF0000FF);
	dim := 10
	for y in 0..<dim {
		for x in 0..<dim {
			pitch_in_u32 := backbuffer.dim[0]
			// This idx calculation is wrong, it just doesn't let the program crash :|
			idx := i32(y+posy) * i32(pitch_in_u32) + i32(x+posx)
			if idx > 0 && idx < i32(backbuffer.dim[0] * backbuffer.dim[1]) {
				backbuffer.bitmap_memory[u32(idx)] = color;
			}
		}
	}
}

// TODO: should probably add codepaths for MONO/STEREO
update_audio :: proc(audio_out : ^Game_Audio_Output_Buffer, tone_hz : i16, offset_x : i32, offset_y : i32) {
	volume := f32(0.05)
	for frame_idx:=0; frame_idx < len(audio_out.samples_to_write); {
		for channel in 0..<audio_out.channel_num {
			freq := i32(tone_hz) + offset_x + offset_y
			phase := f32(audio_out.current_sine_sample*int(freq)) / f32(audio_out.sample_rate)
			audio_out.samples_to_write[i32(frame_idx)+channel] = math.sin_f32(phase*2*math.PI) * volume
		}
		audio_out.current_sine_sample+=1
		frame_idx += int(audio_out.channel_num)
	}
}

@(export)
game_update_and_render :: proc(memory : ^Game_Memory, input : ^Game_Input, buffer : ^Game_Offscreen_Buffer, audio_out : ^Game_Audio_Output_Buffer) {
	// NOTE(inv): For now permanent_storage holds just the game state..
	game_state : ^Game_State = auto_cast memory.permanent_storage
	if !memory.is_initialized {
		game_state.tone_hz = 440

		memory.is_initialized = true

		game_state.player_x = 100
		game_state.player_y = 100

		/*
		data := platform_read_entire_file("sdl3_handmade.exe")
		assert(len(data) > 0)
		platform_write_entire_file("sdl3_handmade_copy.exe", data)
		*/
	}
	//game_state.offset_x += 1

	when false {
		update_audio(audio_out, game_state.tone_hz, game_state.offset_x, game_state.offset_y)
	}
	render_weird_gradient(buffer, game_state.offset_x, game_state.offset_y)
	if input.controllers[0].buttons[.MOVE_UP].ended_down do game_state.player_y-=1
	if input.controllers[0].buttons[.MOVE_DOWN].ended_down do game_state.player_y+=1
	if input.controllers[0].buttons[.MOVE_LEFT].ended_down do game_state.player_x-=1
	if input.controllers[0].buttons[.MOVE_RIGHT].ended_down do game_state.player_x+=1
	render_player(buffer, game_state.player_x, game_state.player_y)

	for idx in 0..<5 {
		if input.controllers[0].mouse_buttons[idx].ended_down {
			render_player(buffer, 200 + 20 * idx, 200)

		}
	}

}
