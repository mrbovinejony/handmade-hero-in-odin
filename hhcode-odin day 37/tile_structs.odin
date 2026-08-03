package handmade
import "base:intrinsics"
import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import win "core:sys/windows"
import xpt "vendor:odin-xinput/xinput"
import "vendor:windows/GameInput"
import xaudio2 "vendor:windows/XAudio2"

Tile_Chunk_Position :: struct{
	tile_chunk_x, tile_chunk_y, tile_chunk_z, rel_tile_x, rel_tile_y : u32
}

Tile_Map_Position :: struct{
	abs_tile_x, abs_tile_y, abs_tile_z : u32,
	//offset from center
	offset_x, offset_y : f32
}

Tile_Chunk :: struct{
	tiles : []u32
}

Tile_Map :: struct{
	tile_chunks : []Tile_Chunk,
	chunk_shift, chunk_mask, chunk_dim : u32,

	tile_chunk_count_x, tile_chunk_count_y, tile_chunk_count_z : i32,

	tile_side_in_meters,  meters_to_pixels : f32,
	tile_side_in_pixels : i32,
}