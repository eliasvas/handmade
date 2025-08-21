package handmade

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
			color :=
				(u32(i32(x)%255+offset_x)%255 << backbuffer.px_info.g_shift) |
				(u32(i32(y)%255+offset_y)%255 << backbuffer.px_info.b_shift)
			backbuffer.bitmap_memory[u32(y) * pitch_in_u32 + u32(x)] = color;
		}
	}
}

// TODO: should probably add codepaths for MONO/STEREO
update_audio :: proc(audio_out : ^Game_Audio_Output_Buffer, offset_x : i32, offset_y : i32) {
	volume := f32(0.005)
	for &sample, idx in audio_out.samples_to_write{
		freq := 440 + offset_x + offset_y
		phase := f32(audio_out.current_sine_sample*int(freq)) / f32(audio_out.sample_rate)
		sample = math.sin_f32(phase*2*math.PI) * volume
		audio_out.current_sine_sample+=1
	}
}

game_update_and_render :: proc(buffer : ^Game_Offscreen_Buffer, audio_out : ^Game_Audio_Output_Buffer, blue_offset : i32, green_offset : i32) {
	update_audio(audio_out, blue_offset, green_offset)
	render_weird_gradient(buffer, blue_offset, green_offset)
}
