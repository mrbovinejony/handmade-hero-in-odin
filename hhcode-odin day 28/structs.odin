package handmade
import "vendor:windows/GameInput"
import "core:flags"
import "base:runtime"
import "base:intrinsics"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:math"
import win "core:sys/windows"
import xpt "vendor:odin-xinput/xinput"
import xaudio2 "vendor:windows/XAudio2"

kilobytes :: proc(val : u64) -> u64{
	return val * u64(1024)
}
megabytes :: proc(val : u64) -> u64{
	return kilobytes(val) * u64(1024)
}
gigabytes :: proc(val : u64) -> u64{
	return megabytes(val) * u64(1024)
}
terabytes :: proc(val : u64) -> u64{
	return gigabytes(val) * u64(1024)
}

Color :: struct {
	r, g, b, a: u8
}

Game_Backbuffer :: struct {
	info:            win.BITMAPINFO,
	memory:          rawptr,
	width:           i32,
	height:          i32,
	pitch:           i32,
	bytes_per_pixel: i32,
}

Win32_Window_Dimension :: struct {
	width:  i32,
	height: i32,
}

Game_Memory :: struct{
	permanent_storage_size : u64,
	permanent_storage : rawptr,
	transient_storage_size : u64,
	transient_storage : rawptr,

	is_initialized : bool
}

Game_State :: struct{
	player_x, player_y : f32
}

Game_Button_State :: struct{
    half_transition_count : i32,
    ended_down : bool
}

Game_Controller_Input :: struct{
    is_analog, is_connected : bool,
    stick_average_x, stick_average_y: f32,

	using _: struct #raw_union{
		buttons: [12]Game_Button_State,
		using _: struct{
			action_up : Game_Button_State,
			action_down : Game_Button_State,
			action_left : Game_Button_State,
			action_right : Game_Button_State,

			move_up : Game_Button_State,
			move_down : Game_Button_State,
			move_right : Game_Button_State,
			move_left : Game_Button_State,
			
			left_shoulder : Game_Button_State,
			right_shoulder : Game_Button_State,
			start : Game_Button_State,
			back : Game_Button_State,

			terminator : Game_Button_State
		}
	}
}

Game_Input :: struct{
    controllers : [5]Game_Controller_Input,

	mouse_buttons : [5]Game_Button_State,
	mouse_x, mouse_y, mouse_z : i32,

	dt_for_frame : f32
}

Debug_Read_File_Result :: struct{
	contents_size : u32,
	contents : rawptr
}

Recorded_Input :: struct{
	input_count : i32,
	input_stream : Game_Input,
}

Win32_State :: struct{
	input_recording_index : i32,
	input_playback_index : i32,
	
	total_size : u64,
	game_memory_block : rawptr,

	recording_handle : win.HANDLE,
	//recording_handle : ^os.File,
	playback_handle : win.HANDLE
	//playback_handle : ^os.File
}

Thread_Context :: struct{
	placeholder : int
}
