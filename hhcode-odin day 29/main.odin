package handmade

import "core:bufio"
import "core:path/slashpath"
import "base:intrinsics"
import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:mem"
import win "core:sys/windows"
import "vendor:windows/GameInput"
import xaudio2 "vendor:windows/XAudio2"

global_running: bool
global_backbuffer: Game_Backbuffer
global_game_input: Game_Input
global_perf_count_frequency : f64

TILE_MAP_COUNT_X :: int
TILE_MAP_COUNT_Y :: int

//i found there was a lot of typedef and define junk when dealing with c in this tutorial,
// these next 4 lines work just fine for now

//fix out of bounds for player, in resizedibsection change mem_commit to mem_reserve

XInputGetState :: #type proc(dw_user_index: win.DWORD, p_state: ^win.XINPUT_STATE)
XInputSetState :: #type proc(dw_user_index: win.DWORD, p_vibration: ^win.XINPUT_VIBRATION)

xpt_get_state: ^XInputGetState
xpt_set_state: ^XInputSetState

global_wfx: win.WAVEFORMATEX
global_source_voice: ^xaudio2.IXAudio2SourceVoice

global_x_offset: i32
global_y_offset: i32

main :: proc() {
	win32_state : Win32_State

	game_memory: Game_Memory
	game_memory.permanent_storage_size = megabytes(64)
	game_memory.transient_storage_size = gigabytes(1)

	game_memory.transient_storage = win.VirtualAlloc(
		nil,
		uint(game_memory.transient_storage_size),
		win.MEM_RESERVE | win.MEM_COMMIT,
		win.PAGE_READWRITE,
	)

	win32_state.total_size = (game_memory.permanent_storage_size + game_memory.transient_storage_size)
	win32_state.game_memory_block = win.VirtualAlloc(nil, win.size_t(win32_state.total_size), win.MEM_RESERVE | win.MEM_COMMIT, win.PAGE_READWRITE)

	game_memory.permanent_storage = win32_state.game_memory_block
	game_memory.transient_storage = rawptr(uintptr(game_memory.permanent_storage) + uintptr(game_memory.permanent_storage_size))

	game_input: [2]Game_Input
	old_input := &game_input[0]
	new_input := &game_input[1]

	perf_count_frequency_result: win.LARGE_INTEGER
	win.QueryPerformanceFrequency(&perf_count_frequency_result)
	global_perf_count_frequency = transmute(f64)perf_count_frequency_result
	perf_count_frequency := transmute(f64)perf_count_frequency_result
	last_counter := win32_get_wall_clock()

	monitor_refresh_hz : int = 60
	game_update_hz := monitor_refresh_hz/2
	target_second_per_frame : f32 = 1.0/ f32(game_update_hz)

	//equivalent to __rdtsc() need import "base:intrinsics"
	last_cycle_count := f64(intrinsics.read_cycle_counter())

	//win32_init_xaudio()
	win32_load_xinput()

	instance := win.HINSTANCE(win.GetModuleHandleW(nil))

	win32_resize_dib_section(&global_backbuffer, 960, 540)

	window_class: win.WNDCLASSW = {
		style         = win.CS_HREDRAW | win.CS_VREDRAW,
		lpfnWndProc   = win32_main_window_callback,
		hInstance     = instance,
		lpszClassName = win.L("HandmadeHeroWindowClass"),
	}

	if win.RegisterClassW(&window_class) == 0 {
		fmt.eprintln("Failed to register window class")
		return
	}
	thread : Thread_Context
	
	window := win.CreateWindowExW(
		0,
		window_class.lpszClassName,
		win.L("Handmade Hero"),
		win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
		win.CW_USEDEFAULT,
		win.CW_USEDEFAULT,
		win.CW_USEDEFAULT,
		win.CW_USEDEFAULT,
		nil,
		nil,
		instance,
		nil,
	)

	if window == nil {
		fmt.eprintln("Failed to create window")
		return
	}

	// NOTE: since we specified ONWDC we can just get one device context and use it forever
	device_context := win.GetDC(window)

	global_running = true
	if game_memory.permanent_storage != nil {
		for global_running {
			new_input.dt_for_frame = target_second_per_frame

			old_keyboard_controller : ^Game_Controller_Input = &old_input.controllers[0]
			new_keyboard_controller : ^Game_Controller_Input = &new_input.controllers[0]
			new_keyboard_controller^ = {}
			new_keyboard_controller.is_connected = true

			for i := 0; i < len(new_keyboard_controller.buttons); i += 1{
				new_keyboard_controller.buttons[i].ended_down = old_keyboard_controller.buttons[i].ended_down
			}

			win32_process_pending_messages(new_keyboard_controller, &win32_state)

			game_buffer : Game_Backbuffer
			game_buffer.memory = global_backbuffer.memory
			game_buffer.bytes_per_pixel = global_backbuffer.bytes_per_pixel
			game_buffer.width = global_backbuffer.width
			game_buffer.height = global_backbuffer.height
			game_buffer.pitch = game_buffer.width * game_buffer.bytes_per_pixel

			if win32_state.input_recording_index != 0{
				debug_record_input(&win32_state, new_input)
			}
			if win32_state.input_playback_index != 0{
				win32_playback_input(&win32_state, new_input)
			}

			point : win.POINT
			win.GetCursorPos(&point)
			//win.ScreenToClient(window, &point)
			new_input.mouse_x = point.x
			new_input.mouse_y = point.y

			new_input.mouse_buttons[0].ended_down = i32(win.GetKeyState(win.VK_LBUTTON)) & i32(1 << 15) != 0
			new_input.mouse_buttons[1].ended_down = i32(win.GetKeyState(win.VK_RBUTTON)) & i32(1 << 15) != 0
			new_input.mouse_buttons[2].ended_down = i32(win.GetKeyState(win.VK_MBUTTON)) & i32(1 << 15) != 0
			new_input.mouse_buttons[3].ended_down = i32(win.GetKeyState(win.VK_XBUTTON1)) & i32(1 << 15) != 0
			new_input.mouse_buttons[4].ended_down = i32(win.GetKeyState(win.VK_XBUTTON2)) & i32(1 << 15) != 0

			win32_update_xinput(old_input, new_input)
			game_update_and_render(&game_memory, &game_buffer, new_input)

			work_counter := win32_get_wall_clock()
			work_seconds_elapsed := win32_get_seconds_elapsed(last_counter, work_counter)

			seconds_elapsed_for_frame := work_seconds_elapsed
			
			desired_scheduler_ms : u32 = 1
			sleep_is_granular := (win.timeBeginPeriod(desired_scheduler_ms) == win.TIMERR_NOERROR)
			if seconds_elapsed_for_frame < target_second_per_frame{
				for seconds_elapsed_for_frame < target_second_per_frame{
					if sleep_is_granular{
						sleep_ms := win.DWORD(1000.0 * (target_second_per_frame - seconds_elapsed_for_frame))
						if sleep_ms > 0{
							win.Sleep(sleep_ms)
						}
					}
						seconds_elapsed_for_frame = win32_get_seconds_elapsed(last_counter, win32_get_wall_clock())	
				}
			}else{
				fmt.println("missed frame rate")
			}

			dimension := win32_get_window_dimension(window)		
			win32_update_window(
				device_context,
				dimension.width,
				dimension.height,
				global_backbuffer,
			)

			temp := old_input
			old_input = new_input
			new_input = temp

			end_counter := win32_get_wall_clock()
			ms_per_frame := 1000.0 * win32_get_seconds_elapsed(last_counter, end_counter)
			last_counter = end_counter

			end_cycle_count := f64(intrinsics.read_cycle_counter())
			cycles_elapsed := end_cycle_count - last_cycle_count
			last_cycle_count = end_cycle_count

			fps := 0
			
			mega_cycles_per_frame := cycles_elapsed / (1000 * 1000)
			fps_buffer: [32]byte
			fps_slice := fmt.bprintf(fps_buffer[:], "fps: %f ", fps)

			ms_per_frame_buffer: [32]byte
			ms_per_frame_slice := fmt.bprintf(
				ms_per_frame_buffer[:],
				"ms_per_frame: %f",
				ms_per_frame,
			)

			mega_cycles_buffer: [32]byte
			mega_cycles_slice := fmt.bprintf(
				mega_cycles_buffer[:],
				" mega cycles: %f",
				mega_cycles_per_frame,
			)

			fps_val := string(fps_slice)
			ms_per_frame_val := string(ms_per_frame_slice)
			mega_cycles_val := string(mega_cycles_slice)

			str_val := strings.concatenate({fps_val, ms_per_frame_val, mega_cycles_val})
			//fmt.println(str_val)


		}
	}
}



game_update_and_render :: proc(p_game_memory: ^Game_Memory, p_buffer: ^Game_Backbuffer, p_input: ^Game_Input) {
	//assert((&p_game_input.controllers[0].terminator - &p_game_input.controllers[0].buttons[0]) == (len(p_game_input.controllers[0].buttons)))
	game_state := (^Game_State)(p_game_memory.permanent_storage)
	assert(size_of(Game_State) <= p_game_memory.permanent_storage_size)

	upper_left_x := f32(0.0)
	upper_left_y := f32(0.0)
	tile_width := f32(60.0)
	tile_height := f32(60.0)

	tile_count_x :: 17 //column
	tile_count_y :: 9 //row

	tiles00: [][]u32 = {
		{1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1},
		{1, 1, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1},
		{1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 0},
		{1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1},
		{1, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1},
		{1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1},
		{1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1},
	}

	tiles01: [][]u32 = {
	    {1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 0},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1},
	}

	tiles10: [][]u32 = {
	    {1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 0},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1},
	}

	tiles11: [][]u32 = {
	    {1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 0},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0, 1},
		{1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1, 1},
	}

	tile_maps : [2][2]Tile_Map

	tile_maps[0][0].count_x = tile_count_x
	tile_maps[0][0].count_y = tile_count_y
	tile_maps[0][0].upper_left_x = 0
	tile_maps[0][0].tile_width = 60
	tile_maps[0][0].tile_height = 60
	tile_maps[0][0].tiles = set_tile_map_data(tiles00, tile_count_x, tile_count_y)

	tile_maps[0][1] = tile_maps[0][0]
	tile_maps[0][1].tiles = set_tile_map_data(tiles01, tile_count_x, tile_count_y)

	tile_maps[1][0] = tile_maps[0][0]
	tile_maps[1][0].tiles = set_tile_map_data(tiles10, tile_count_x, tile_count_y)

	tile_maps[1][1] = tile_maps[0][0]
	tile_maps[1][1].tiles = set_tile_map_data(tiles11, tile_count_x, tile_count_y)

	current_tile_map := &tile_maps[0][0]

	world : World
	world.count_x = 2
	world.count_y = 2
	world.all_tile_maps = set_world_map_data(tile_maps, 2, 2)

	player_width := 0.75 * current_tile_map.tile_width
	player_height := current_tile_map.tile_height

	if p_game_memory.is_initialized == false {
		game_state.player_x = 150
		game_state.player_y = 150

		p_game_memory.is_initialized = true
	}
	delta : i32= 5

	for i := 0; i < len(p_input.controllers); i +=1{
		controller_input := p_input.controllers[i]
		if controller_input.is_analog{

		}else{
			d_player_x := f32(0.0)
			d_player_y := f32(0.0)

			if controller_input.move_right.ended_down{
				d_player_x = 1.0
				fmt.println(d_player_x)
			}
			if controller_input.move_left.ended_down{
				d_player_x = -1.0
			}
			if controller_input.move_down.ended_down{
				d_player_y = 1.0
			}
			if controller_input.move_up.ended_down{
				d_player_y = -1
			}

			d_player_x = d_player_x * 64.0
			d_player_y = d_player_y * 64.0

			new_player_x := game_state.player_x + p_input.dt_for_frame * d_player_x
			new_player_y := game_state.player_y + p_input.dt_for_frame * d_player_y

			if is_tile_map_point_empty(current_tile_map, new_player_x, new_player_y) && 
				is_tile_map_point_empty(current_tile_map, new_player_x - 0.5 * player_width, new_player_y) &&
				is_tile_map_point_empty(current_tile_map, new_player_x + 0.5 * player_width, new_player_y){
				game_state.player_x = new_player_x
				game_state.player_y = new_player_y

			}
		}
	}
	
	draw_rectangle(p_buffer, 0, 0, f32(p_buffer.width), f32(p_buffer.height), 1.0, 0.0, 1.0)

	for row := 0; row < current_tile_map.count_y; row += 1{
		for column := 0; column < current_tile_map.count_x; column += 1{
			tile_id := get_tile_value_unchecked(current_tile_map, f32(column), f32(row))
			gray := f32(0.5)
			if tile_id == 1{
				gray = 1.0
			}

			min_x := current_tile_map.upper_left_x + f32(column) * tile_width
			min_y := current_tile_map.upper_left_y + f32(row) * tile_height
			max_x := min_x + current_tile_map.tile_width
			max_y := min_y + current_tile_map.tile_height

			draw_rectangle(p_buffer, 
				min_x, 
				min_y, 
				max_x,
				max_y, 
				 gray, gray, gray)
		} 
	}
	player_r := f32(1.0)
	player_g := f32(1.0)
	player_b := f32(0.0)

	player_left := game_state.player_x - (0.5 * player_width)
	player_top := game_state.player_y - player_height

	draw_rectangle(p_buffer, player_left, player_top, player_left + player_width, player_top + player_height, player_r, player_g, player_b)
}




render_player :: proc(p_buffer: ^Game_Backbuffer, p_player_x, p_player_y: i32) {
	pixel := ([^]u32)(p_buffer.memory)

	color := 0xFFFFFFFF
	left := p_player_x
	top := p_player_y
	right := p_player_x + 10
	bottom := p_player_y + 10
	width := 10
	height := i32(10)

	start := p_buffer.memory
	end_of_buffer := cast(^byte)(uintptr(start) + uintptr(p_buffer.pitch * p_buffer.height))

	slice := pixel[0:p_buffer.width * p_buffer.height]

	if p_player_x >= 0 && p_player_x < p_buffer.width - 10 && p_player_y >= 0 && p_player_y < p_buffer.height - 40{
		for x := left; x < right; x += 1{
			for y := top; y < bottom; y += 1{
				x_bit := (x + p_player_x)
				y_bit := (y + p_player_y)

					slice[y_bit * p_buffer.width + x_bit] = u32(color)
				
			}
		}
	}
}



is_tile_map_point_empty :: proc(p_tile_map : ^Tile_Map, p_new_x, p_new_y : f32) -> bool{
	is_valid := false

	tile_x := truncate_real32_to_int((p_new_x - p_tile_map.upper_left_x) / p_tile_map.tile_width)
	tile_y := truncate_real32_to_int((p_new_y - p_tile_map.upper_left_y) / p_tile_map.tile_height) 
			
	if tile_x >= 0 && tile_x < p_tile_map.count_x && tile_y >= 0 && tile_y < p_tile_map.count_y{
		tile_map_value := get_tile_value_unchecked(p_tile_map, f32(tile_x), f32(tile_y))
		is_valid = tile_map_value == 0
	}

	return is_valid
}

get_tile_map :: proc(p_world : ^World, p_tile_map_x, p_tile_map_y : i32) -> Tile_Map{
	tile_map : ^Tile_Map

	if p_tile_map_x >= 0 && p_tile_map_x < i32(p_world.count_x) && p_tile_map_y >= 0 && p_tile_map_y < i32(p_world.count_y){
		tile_map = &p_world.all_tile_maps[p_tile_map_y * i32(p_world.count_x) + p_tile_map_x]
	}
	return tile_map^
}

is_world_point_empty :: proc(p_world : ^World, p_test_x, p_test_y : f32, p_tile_map_x, p_tile_map_y : i32) -> bool{
	is_empty := false

	tile_map := get_tile_map(p_world, p_tile_map_x, p_tile_map_y)

		is_empty = is_tile_map_point_empty(&tile_map, p_test_x, p_test_y)
	

	return is_empty
}

get_tile_value_unchecked :: proc(p_tile_map : ^Tile_Map, p_tile_x, p_tile_y : f32) -> u32{
	tile_map_value := p_tile_map.tiles[int(p_tile_y * f32(p_tile_map.count_x) + p_tile_x)]
	return tile_map_value
}

draw_rectangle :: proc(p_buffer : ^Game_Backbuffer, p_real_min_x, p_real_min_y, p_real_max_x, p_real_max_y : f32, R, G, B : f32){
	min_x := round_real32_to_int32(p_real_min_x)
	min_y := round_real32_to_int32(p_real_min_y)
	max_x := round_real32_to_int32(p_real_max_x)
	max_y := round_real32_to_int32(p_real_max_y)

	pixel := ([^]u32)(p_buffer.memory)

	color := u32(round_real32_to_uint32(R * 255.0) << 16) | (round_real32_to_uint32(G * 255.0) << 8) | (round_real32_to_uint32(B * 255.0))

	if min_x <0{
		min_x = 0
	}
	if(min_y < 0){
		min_y = 0
	}
	if max_x > p_buffer.width{
		max_x = p_buffer.width
	}
	if max_y > p_buffer.height{
		max_y = p_buffer.height
	}

	for y := min_y; y < max_y; y += 1{
		for x := min_x; x < max_x; x += 1{
			x_bit := x + min_x
			y_bit := y + min_y

			pixel[y * p_buffer.width + x] = color
		}
	}
}

set_tile_map_data :: proc(p_tiles : [][]u32, p_count_x, p_count_y : int) -> []u32{
	tile_data := make([]u32, p_count_x * p_count_y)

	for y := 0; y < p_count_y; y += 1{
		for x := 0; x < p_count_x; x += 1{
			index := y * p_count_x + x
			tile_data[index] = p_tiles[y][x]
		}
	}

	return tile_data
}

set_world_map_data :: proc(p_maps : [2][2]Tile_Map, p_count_x, p_count_y : int) -> []Tile_Map{
	map_data := make([]Tile_Map, p_count_x * p_count_y)

	for y := 0; y < p_count_y; y += 1{
		for x := 0; x < p_count_x; x += 1{
			index := y * p_count_x + x
			map_data[index] = p_maps[y][x]
		}
	}

	return map_data
}
