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
  tiles : []i32,
}
World :: struct {
	count : [2]i32, // same count for all tilemaps sadly
	upper_left : [2]f32,
	tile_dim : [2]f32,
	
	tilemap_count : [2]i32,
	tilemaps : []Tile_Map,
}
Canonical_Position :: struct {
  tilemap_idx : [2]i32, // reference tilemap
  tile_coords : [2]i32, // which tiles
  tile_rel_coords : [2]f32, // relative offset 
}
Raw_Position :: struct {
  tilemap_idx : [2]i32, // Which tilemap this Raw_Position uses
  tile_coords : [2]f32, // Which tiles inside the tilemap are referenced
}

get_tilemap_from_world :: proc(w : ^World, tilemap_idx : [2]i32) -> ^ Tile_Map {
	if tilemap_idx.x > w.tilemap_count.x || tilemap_idx.y > w.tilemap_count.y do return nil
	return &w.tilemaps[w.tilemap_count.x*tilemap_idx.y + tilemap_idx.x]
}
tilemap_is_tile_empty :: proc(w : ^World, tm : ^Tile_Map, tile_coords : [2]i32) -> bool {
	if tile_coords.x > w.count.x || tile_coords.y > w.count.y do return false
	return get_tilemap_value(w, tm, tile_coords) == 0
}

get_tilemap_value :: proc(w : ^World, tm : ^Tile_Map, tile_coords : [2]i32) -> i32{
	return tm.tiles[tile_coords.y*w.count.x + tile_coords.x]
}

is_world_point_empty :: proc(w : ^World, raw_pos : Raw_Position) -> bool {
  empty := false
  can_pos := get_canonical_position(w, raw_pos)
  //fmt.println("raw:", raw_pos, "can: ", can_pos)
  tm := get_tilemap_from_world(w, can_pos.tilemap_idx)
  empty = tilemap_is_tile_empty(w, tm, can_pos.tile_coords)
  return empty
}

get_canonical_position :: proc(w : ^World, raw_pos : Raw_Position) -> Canonical_Position {
  p : Canonical_Position

  p.tile_coords = {
    i32(raw_pos.tile_coords.x / f32(w.tile_dim.x)),
    i32(raw_pos.tile_coords.y / f32(w.tile_dim.y)),
  }
  p.tile_rel_coords = {
    raw_pos.tile_coords.x - f32(p.tile_coords.x)*w.tile_dim.x,
    raw_pos.tile_coords.y - f32(p.tile_coords.y)*w.tile_dim.y,
  }

  // TODO: also add transition logic for the tilemaps instead of this
  p.tilemap_idx = raw_pos.tilemap_idx

  if p.tile_coords.x >= w.count.x {
    p.tile_coords.x = p.tile_coords.x - w.count.x
    p.tilemap_idx.x += 1
  }
  if p.tile_coords.y >= w.count.y {
    p.tile_coords.y = p.tile_coords.y - w.count.y
    p.tilemap_idx.y += 1
  }

  if p.tile_coords.x < 0 {
    p.tile_coords.x = w.count.x + p.tile_coords.x
    p.tilemap_idx.x -= 1
  }

  if p.tile_coords.y < 0 {
    p.tile_coords.y = w.count.y + p.tile_coords.y
    p.tilemap_idx.y -= 1
  }

  return p
}


// TODO: this is too slow I think, @speedup
draw_rect :: proc(backbuffer : ^g.Game_Offscreen_Buffer, posx : f32, posy : f32, w : f32, h : f32, red : f32, green : f32, blue : f32) {
	BLACKNESS :: u32(0)
	for y in 0..<int(h) {
		for x in 0..<int(w){
			pitch_in_u32 := backbuffer.dim[0]
			// This idx calculation is wrong, it just doesn't let the program crash :|
			color := BLACKNESS 
			color |= (u32(red*255.0) << backbuffer.px_info.r_shift)
			color |= (u32(green*255.0) << backbuffer.px_info.g_shift)
			color |= (u32(blue*255.0) << backbuffer.px_info.b_shift)

      xcoord := i32(x+int(posx))
      ycoord := i32(y+int(posy)) 
      //if xcoord > 0 && xcoord < i32(backbuffer.dim[0]) && ycoord > 0 && ycoord < i32(backbuffer.dim[1]) {
      if xcoord > 0 && xcoord < i32(backbuffer.dim[0]) && ycoord > 0 {
        idx := xcoord + ycoord * i32(pitch_in_u32)
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

		game_state.player = {200,250}

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
	tm0 := Tile_Map {
    tiles = {
			1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,1,1, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,0,
			1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,1,1, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,1,1,1, 1,1,0,0, 0,1,1,1, 1,1,1,1,
		},
	}
	tm1 := Tile_Map {
    tiles = {
			1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,1,
			0,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,1,1,1, 1,1,0,0, 0,1,1,1, 1,1,1,1,
		},
	}
	tm2 := Tile_Map {
    tiles = {
			1,1,1,1, 1,1,0,0, 0,1,1,1, 1,1,1,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,1,
			0,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1,
		},
	}
	tm3 := Tile_Map {
    tiles = {
			1,1,1,1, 1,1,0,0, 0,1,1,1, 1,1,1,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,0,0,0, 0,1,0,1, 0,1,0,0, 0,0,0,1,
			1,0,0,0, 0,1,0,1, 0,1,0,0, 0,0,0,1,
			1,0,0,0, 0,1,0,1, 0,1,0,0, 0,0,0,0,
			1,0,0,0, 0,1,0,1, 0,1,0,0, 0,0,0,1,
			1,0,0,0, 0,1,0,1, 0,1,0,0, 0,0,0,1,
			1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1,
			1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1,
		},
	}

	w := World {
		count = {16, 9},
		upper_left = {0,0},
		tile_dim = {TILE_PX_W, TILE_PX_H},
		tilemap_count = {2,2},
		tilemaps = { tm0,tm1,tm3,tm2 },
	}

	// RENDERING CODE
	draw_rect(buffer, 0, 0, auto_cast buffer.dim[0], auto_cast buffer.dim[1], 0.4,0.4,0.95)
	for row in 0..<16 {
		for col in 0..<9 {
			tile_val := get_tilemap_value(&w, get_tilemap_from_world(&w, game_state.tilemap_idx), {auto_cast row, auto_cast col})
			color := f32(tile_val) * 0.85
			if tile_val > 0 {
				draw_rect(buffer, f32(row)*TILE_PX_W, f32(col)*TILE_PX_H, TILE_PX_W, TILE_PX_H, color,color,color)
			}
		}
	}
	draw_rect(buffer, game_state.player.x - TILE_PX_W/2, game_state.player.y - TILE_PX_H, TILE_PX_W, TILE_PX_H, 1,0,0)

	// MOVEMENT CODE
	speed := f32(200)
	new_player_pos := game_state.player

	if input.controllers[0].buttons[.MOVE_UP].ended_down do new_player_pos.y -=speed*input.dt
	if input.controllers[0].buttons[.MOVE_DOWN].ended_down do new_player_pos.y +=speed*input.dt
	if input.controllers[0].buttons[.MOVE_LEFT].ended_down do new_player_pos.x -=speed*input.dt
	if input.controllers[0].buttons[.MOVE_RIGHT].ended_down do new_player_pos.x +=speed*input.dt

  raw_pos := Raw_Position{
    tilemap_idx = game_state.tilemap_idx,
    tile_coords = new_player_pos,
  }
  can_pos := get_canonical_position(&w, raw_pos)

  left_pos := Raw_Position{
    tilemap_idx = raw_pos.tilemap_idx,
    tile_coords = raw_pos.tile_coords - [2]f32{w.tile_dim.x/2, 0},
  }
  right_pos := Raw_Position{
    tilemap_idx = raw_pos.tilemap_idx,
    tile_coords = raw_pos.tile_coords + [2]f32{w.tile_dim.x/2, 0},
  }

  lempty := is_world_point_empty(&w, left_pos)
  rempty := is_world_point_empty(&w, right_pos)

  if lempty && rempty {
    game_state.tilemap_idx = can_pos.tilemap_idx
		game_state.player = w.upper_left + w.tile_dim *
      {f32(can_pos.tile_coords.x), f32(can_pos.tile_coords.y)} + can_pos.tile_rel_coords
  }
}
