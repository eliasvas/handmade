package game

import g "../game_api"
import "base:runtime"
import "core:fmt"
import "base:intrinsics"
import "core:strings"
import "core:time"
import "core:math"
import "core:c"

Tile_Map :: struct {
	count : [2]u32,
	upper_left : [2]f32,
	tile_dim : [2]f32,
	tiles : []u32,
}
World :: struct {
	tile_count : [2]u32,
	tilemaps : []Tile_Map,
}
get_tilemap_from_world :: proc(w : ^World, tilemap_idx : [2]u32) -> ^ Tile_Map {
	if tilemap_idx.x > w.tile_count.x || tilemap_idx.y > w.tile_count.y do return nil
	return &w.tilemaps[w.tile_count.x*tilemap_idx.y + tilemap_idx.x]
}
tilemap_is_tile_empty :: proc(tm : ^Tile_Map, tile_idx : [2]u32) -> bool {
	if tile_idx.x > tm.count.x || tile_idx.y > tm.count.y do return false
	return get_tilemap_value(tm, tile_idx) == 0
}

get_tilemap_value :: proc(tm : ^Tile_Map, tile_idx : [2]u32) -> u32{
	return tm.tiles[tile_idx.y*tm.count.x + tile_idx.x]
}

// TODO: this is too slow I think, @speedup
draw_rect :: proc(backbuffer : ^g.Game_Offscreen_Buffer, posx : f32, posy : f32, w : f32, h : f32, red : f32, green : f32, blue : f32) {
	/*
	black := u32(0xFFFFFFFF)
	black ~= (u32(0xFF) << backbuffer.px_info.r_shift)
	black ~= (u32(0xFF) << backbuffer.px_info.b_shift)
	black ~= (u32(0xFF) << backbuffer.px_info.b_shift)
	*/
	black := u32(0)
	for y in 0..<int(h) {
		for x in 0..<int(w){
			pitch_in_u32 := backbuffer.dim[0]
			// This idx calculation is wrong, it just doesn't let the program crash :|
			color := black
			color |= (u32(red*255.0) << backbuffer.px_info.r_shift)
			color |= (u32(green*255.0) << backbuffer.px_info.g_shift)
			color |= (u32(blue*255.0) << backbuffer.px_info.b_shift)

			idx := i32(y+int(posy)) * i32(pitch_in_u32) + i32(x+int(posx))
			if idx > 0 && idx < i32(backbuffer.dim[0] * backbuffer.dim[1]) {
				backbuffer.bitmap_memory[u32(idx)] = color;
			}
		}
	}
}

// TODO: should probably add codepaths for MONO/STEREO
update_audio :: proc(audio_out : ^g.Game_Audio_Output_Buffer, tone_hz : i16, offset_x : i32, offset_y : i32) {
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
game_update_and_render :: proc(memory : ^g.Game_Memory, input : ^g.Game_Input, buffer : ^g.Game_Offscreen_Buffer, audio_out : ^g.Game_Audio_Output_Buffer) {
	// NOTE(inv): For now permanent_storage holds just the game state..
	game_state : ^g.Game_State = auto_cast memory.permanent_storage
	if !memory.is_initialized {
		game_state.tone_hz = 440

		memory.is_initialized = true

		game_state.player = {100,100}

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

	// TILE BULLSHIT
	TILE_PX_W :: 50
	TILE_PX_H :: 50
	tm01 := Tile_Map {
		count = {16, 9},
		upper_left = {0,0},
		tile_dim = {TILE_PX_W, TILE_PX_H},
		tiles = {
			1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,0,1,1, 0,0,0,0, 1,0,0,0, 0,0,0,1,
			1,1,1,0, 0,0,0,0, 1,1,0,0, 0,0,0,1,
			0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
			1,1,1,0, 0,0,0,0, 1,1,0,0, 0,0,0,1,
			1,0,1,1, 0,0,0,0, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1,
		},
	}
	w := World {
		tile_count = {2,2},
		tilemaps = { tm01,tm01,tm01,tm01 },
	}

	tilemap_idx := [2]u32{0,0}

	// RENDERING CODE
	draw_rect(buffer, 0, 0, auto_cast buffer.dim[0], auto_cast buffer.dim[1], 0.4,0.4,0.95)
	for row in 0..<16 {
		for col in 0..<9 {
			tile_val := get_tilemap_value(get_tilemap_from_world(&w, tilemap_idx), {auto_cast row, auto_cast col})
			color := f32(tile_val) * 0.85
			if tile_val > 0 {
				draw_rect(buffer, f32(row)*TILE_PX_W, f32(col)*TILE_PX_H, TILE_PX_W, TILE_PX_H, color,color,color)
			}
		}
	}
	draw_rect(buffer, game_state.player.x - TILE_PX_W/2, game_state.player.y - TILE_PX_H, TILE_PX_W, TILE_PX_H, 1,0,0)

	// MOVEMENT CODE
	speed := f32(100)
	new_player_pos := game_state.player

	if input.controllers[0].buttons[.MOVE_UP].ended_down do new_player_pos.y -=speed*input.dt
	if input.controllers[0].buttons[.MOVE_DOWN].ended_down do new_player_pos.y +=speed*input.dt
	if input.controllers[0].buttons[.MOVE_LEFT].ended_down do new_player_pos.x -=speed*input.dt
	if input.controllers[0].buttons[.MOVE_RIGHT].ended_down do new_player_pos.x +=speed*input.dt

	tilemap := get_tilemap_from_world(&w, tilemap_idx)
	new_player_tile_pos := new_player_pos / tilemap.tile_dim
	target_tile_empty := tilemap_is_tile_empty(tilemap, {u32(new_player_tile_pos.x), u32(new_player_tile_pos.y)})
	if target_tile_empty {
		game_state.player = new_player_pos
	}

}
