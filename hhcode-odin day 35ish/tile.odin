package handmade

import "base:intrinsics"
import "base:runtime"
import "core:bufio"
import "core:flags"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:path/slashpath"
import "core:strings"
import win "core:sys/windows"
import "vendor:windows/GameInput"
import xaudio2 "vendor:windows/XAudio2"

get_tile_chunk_position :: proc(p_map: ^Tile_Map, p_abs_x, p_abs_y, p_abs_z: u32) -> Tile_Chunk_Position {
	result: Tile_Chunk_Position

	result.tile_chunk_x = p_abs_x >> p_map.chunk_shift
	result.tile_chunk_y = p_abs_y >> p_map.chunk_shift
	result.rel_tile_x = p_abs_x & p_map.chunk_mask
	result.rel_tile_y = p_abs_y & p_map.chunk_mask

	result.tile_chunk_z = p_abs_z
	return result
}

get_tile_chunk :: proc(p_map: ^Tile_Map, p_chunk_x, p_chunk_y, p_chunk_z: i32) -> ^Tile_Chunk {
	tile_chunk: ^Tile_Chunk

	if (p_chunk_x >= 0) && (p_chunk_x < p_map.tile_chunk_count_x) &&
	   (p_chunk_y >= 0) && (p_chunk_y < p_map.tile_chunk_count_y) &&
	   (p_chunk_z >= 0) && (p_chunk_z < p_map.tile_chunk_count_z) {
		tile_chunk = &p_map.tile_chunks[p_chunk_z * p_map.tile_chunk_count_y * p_map.tile_chunk_count_x +
										p_chunk_y * p_map.tile_chunk_count_x +
										 p_chunk_x]
	}

	return tile_chunk
}

recanonicalize_coord :: proc(p_map: ^Tile_Map, p_tile: ^u32, p_tile_rel: ^f32) {
	offset := round_real32_to_int32(p_tile_rel^ / p_map.tile_side_in_meters)
	p_tile^ += u32(offset)
	p_tile_rel^ -= f32(offset) * p_map.tile_side_in_meters

	//assert(p_tile_rel^ >= -0.5 * p_map.tile_side_in_meters)
	//assert(p_tile_rel^ <= 0.5 * p_map.tile_side_in_meters)
}

get_tile_value :: proc(p_map: ^Tile_Map, p_abs_x, p_abs_y, p_abs_z: u32) -> u32 {
	chunk_pos := get_tile_chunk_position(p_map, p_abs_x, p_abs_y, p_abs_z)
	chunk := get_tile_chunk(p_map, i32(chunk_pos.tile_chunk_x), i32(chunk_pos.tile_chunk_y), i32(chunk_pos.tile_chunk_z))
	
	result := u32(0)

	/*tile_chunk_value := get_tile_chunk_value(
		p_map,
		chunk,
		u32(chunk_pos.rel_tile_x),
		u32(chunk_pos.rel_tile_y),
	)*/
	if chunk != nil && chunk.tiles != nil{
		result = chunk.tiles[chunk_pos.rel_tile_y * p_map.chunk_dim + chunk_pos.rel_tile_x]
	}
	return result
}

recanonicalize_position :: proc(p_map: ^Tile_Map, p_pos: Tile_Map_Position) -> Tile_Map_Position {
	result := p_pos

	recanonicalize_coord(p_map, &result.abs_tile_x, &result.tile_rel_x)
	recanonicalize_coord(p_map, &result.abs_tile_y, &result.tile_rel_y)

	return result
}

it_tile_map_empty :: proc(p_map: ^Tile_Map, p_pos: Tile_Map_Position) -> bool {
	tile_chunk_value := get_tile_value(p_map, u32(p_pos.abs_tile_x), u32(p_pos.abs_tile_y), u32(p_pos.abs_tile_z))
	empty := false
	empty = tile_chunk_value == 1
	return empty
}

set_tile_value :: proc( p_map: ^Tile_Map, px, py, pz, pv: u32) {
	chunk_pos := get_tile_chunk_position(p_map, px, py, pz)
	chunk := get_tile_chunk(p_map, i32(chunk_pos.tile_chunk_x), i32(chunk_pos.tile_chunk_y), i32(chunk_pos.tile_chunk_z))
	assert(chunk != nil)

	if chunk.tiles == nil{
		tile_count := p_map.chunk_dim * p_map.chunk_dim
		chunk.tiles = make([]u32, tile_count)
		for tile_index := u32(0); tile_index < tile_count; tile_index += 1{
			chunk.tiles[tile_index] = 1
		}
	}

	chunk.tiles[chunk_pos.rel_tile_y * p_map.chunk_dim + chunk_pos.rel_tile_x] = pv
}














