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

Game_Button_State :: struct{
    half_transition_count : i32,
    ended_down : bool
}

Game_Controller_Input :: struct{
    is_analog : bool,
    start_x, start_y, min_x, min_y, max_x, max_y, end_x, end_y: f32,
    up, down, left, right, left_shoulder, right_shoulder: Game_Button_State,
}

Game_Input :: struct{
    controllers : [4]Game_Controller_Input
}
