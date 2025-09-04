package game_api

import "core:dynlib"
import "core:os"
import "core:fmt"
import "core:c/libc"

Pixel_Format_Info :: struct{
	r_shift : u8,
	g_shift : u8,
	b_shift : u8,
}
Game_Offscreen_Buffer :: struct {
	px_info : Pixel_Format_Info,
	bitmap_memory : []u32,
	dim : [2]u32,
	bytes_per_pixel : u32,
}

Game_Audio_Output_Buffer :: struct {
	current_sine_sample : int, // remove dis
	channel_num : i32,
	sample_rate : i32,

	// game should write all these samples
	// they will be updated to underlying osund buffer
	samples_to_write : []f32,
}

Game_Button_State :: struct {
	half_transition_count : u32,
	ended_down : bool,
}
Game_Button_Kind :: enum {
	ACTION_UP,
	ACTION_DOWN,
	ACTION_LEFT,
	ACTION_RIGHT,

	MOVE_UP,
	MOVE_DOWN,
	MOVE_LEFT,
	MOVE_RIGHT,

	L_SHOULDER,
	R_SHOULDER,
}

Game_Controller_Input :: struct {
	stick_x : f32,
	stick_y : f32,

	mouse_buttons: [5]Game_Button_State,
	mouse_x : f32,
	mouse_y : f32,
	mouse_z : f32, // ??

	buttons : [Game_Button_Kind]Game_Button_State,
}

// 0 -> Keyboard & 1..4 -> Gamepads
Game_Input_Index :: enum { OLD, NEW }
Game_Input :: struct {
	dt : f32,
	controllers : [5] Game_Controller_Input,
}

Game_Memory :: struct {
	is_initialized : bool,

	permanent_storage : rawptr,
	permanent_storage_size : u64,

	transient_storage : rawptr,
	transient_storage_size : u64,
}

Game_State :: struct {
	tone_hz : i16,
	offset_x : i32,
	offset_y : i32,

	player : [2]f32,
	tilemap_idx : [2]i32,
}

Game_API :: struct {
	game_update_and_render : proc(memory : ^Game_Memory, input : ^Game_Input, buffer : ^Game_Offscreen_Buffer, audio_out : ^Game_Audio_Output_Buffer),
	lib: dynlib.Library,
	dll_time: os.File_Time,
}
