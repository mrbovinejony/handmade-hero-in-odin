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

	win32_resize_dib_section(&global_backbuffer, 1280, 720)

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
			new_input.seconds_to_advance_over_update = target_second_per_frame

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

win32_process_pending_messages :: proc(p_keyboard_controller : ^Game_Controller_Input, p_state : ^Win32_State) {
	//assert in process_keyboard_message fails in button cases
	_message: win.MSG

	for win.PeekMessageW(&_message, nil, 0, 0, win.PM_REMOVE) {
		switch _message.message {
		case win.WM_QUIT:
			global_running = false
		case win.WM_SYSKEYDOWN:
			fallthrough
		case win.WM_SYSKEYUP:
			fallthrough
		case win.WM_KEYDOWN:
			fallthrough
		case win.WM_KEYUP:
			is_down: bool = ((_message.lParam & (1 << 31)) == 0)
			was_down: bool = ((_message.lParam & (1 << 30)) != 0)
			alt_key_was_down: bool = ((_message.lParam & (1 << 29)) != 0)

			//vkcode: win.WPARAM does not work
			vk_code := u32(_message.wParam) & 0xFFFF //masks any unintended higher bits
			if is_down != was_down {
				switch vk_code {
				case 'W':
					win32_process_keyboard_message(&p_keyboard_controller.move_up, is_down)
				case 'A':
					win32_process_keyboard_message(&p_keyboard_controller.move_left, is_down)
				case 'S':
					win32_process_keyboard_message(&p_keyboard_controller.move_down, is_down)
				case 'D':
					win32_process_keyboard_message(&p_keyboard_controller.move_right, is_down)
				case 'Q':
					win32_process_keyboard_message(&p_keyboard_controller.left_shoulder, is_down)
					fmt.println("keyboard q left shoulder")
				case 'E':
					win32_process_keyboard_message(&p_keyboard_controller.right_shoulder, is_down)
					fmt.println("keyboard e right shoulder")
				case 'L':
					if is_down{
						fmt.println("l pressed")
						if p_state.input_recording_index == 0{
							debug_begin_recording_input(p_state, 1)
						}else{
							debug_end_recording_input(p_state)
							debug_begin_input_playback(p_state, 1)
						}
					}
				case win.VK_UP:
					win32_process_keyboard_message(&p_keyboard_controller.action_up, is_down)
					fmt.println("keyboard up action up")
				case win.VK_DOWN:
					win32_process_keyboard_message(&p_keyboard_controller.action_down, is_down)
					fmt.println("keyboard down action down")
				case win.VK_LEFT:
					win32_process_keyboard_message(&p_keyboard_controller.action_left, is_down)
					fmt.println("keyboard left action left")
				case win.VK_RIGHT:
					win32_process_keyboard_message(&p_keyboard_controller.action_right, is_down)
					fmt.println("keyboard right action right")
				case win.VK_ESCAPE:
					global_running = false
				case win.VK_SPACE:
					win32_process_keyboard_message(&p_keyboard_controller.start, is_down)
					fmt.println("keyboard space start")
				case win.VK_BACK:
					win32_process_keyboard_message(&p_keyboard_controller.back, is_down)
				case win.VK_F4:
					if alt_key_was_down {
						global_running = false
					}
				}
			}

		case:
			win.TranslateMessage(&_message)
			win.DispatchMessageW(&_message)
		}
	}
}

game_update_and_render :: proc(p_game_memory: ^Game_Memory, p_buffer: ^Game_Backbuffer, p_input: ^Game_Input) {
	//assert((&p_game_input.controllers[0].terminator - &p_game_input.controllers[0].buttons[0]) == (len(p_game_input.controllers[0].buttons)))
	game_state := (^Game_State)(p_game_memory.permanent_storage)
	assert(size_of(Game_State) <= p_game_memory.permanent_storage_size)

	if p_game_memory.is_initialized == false {
		p_game_memory.is_initialized = true
	}
	delta : i32= 5

	//for i := 0; i < len(p_input.controllers); i +=1{
	//	controller_input := p_input.controllers[i]
	draw_rectangle(p_buffer, 0, 0, f32(p_buffer.width), f32(p_buffer.height), 0x00FF00FF)
	draw_rectangle(p_buffer, 10, 10, 30, 30, 0x0000FFFF)
}


win32_process_keyboard_message :: proc(p_new_state : ^Game_Button_State, p_is_down : bool){
	assert(p_new_state.ended_down != p_is_down, "state not equal")

	p_new_state.ended_down = p_is_down
	p_new_state.half_transition_count += 1
}

win32_main_window_callback :: proc "stdcall" (
	window: win.HWND,
	message: win.UINT,
	wparam: win.WPARAM,
	lparam: win.LPARAM,
) -> win.LRESULT {
	context = runtime.default_context()

	result: win.LRESULT

	switch message {
		case win.WM_CLOSE:
			global_running = false

		case win.WM_ACTIVATEAPP:
			fmt.println("WM_ACTIVATEAPP")
		case win.WM_SYSKEYDOWN:
			fallthrough
		case win.WM_SYSKEYUP:
			fallthrough
		case win.WM_KEYDOWN:
			fallthrough
		case win.WM_KEYUP:

		case win.WM_DESTROY:
			global_running = false


		case win.WM_PAINT:
			paint: win.PAINTSTRUCT
			device_context := win.BeginPaint(window, &paint)

			x := paint.rcPaint.left
			y := paint.rcPaint.right
			width := paint.rcPaint.right - paint.rcPaint.left
			height := paint.rcPaint.bottom - paint.rcPaint.top

			dimension := win32_get_window_dimension(window)

			win32_update_window(
				device_context,
				dimension.width,
				dimension.height,
				global_backbuffer,
			)

			win.EndPaint(window, &paint)

		case:
			result = win.DefWindowProcW(window, message, wparam, lparam)
		}

	return result
}

win32_get_window_dimension :: proc(window: win.HWND) -> Win32_Window_Dimension {
	result: Win32_Window_Dimension

	client_rect: win.RECT
	win.GetClientRect(window, &client_rect)
	result.width = client_rect.right - client_rect.left
	result.height = client_rect.bottom - client_rect.top

	return result
}

win32_resize_dib_section :: proc(buffer: ^Game_Backbuffer, width, height: i32) {
	if buffer.memory != nil {
		win.VirtualFree(buffer.memory, 0, win.MEM_RELEASE)
	}

	buffer.width = width
	buffer.height = height
	buffer.bytes_per_pixel = 4

	buffer.info = {
		bmiHeader = {
			biSize = size_of(buffer.info.bmiHeader),
			biWidth = buffer.width,
			biHeight = -buffer.height,
			biPlanes = 1,
			biBitCount = 32,
			biCompression = win.BI_RGB,
		},
	}

	bitmap_memory_size := uint(buffer.width * buffer.height * buffer.bytes_per_pixel)
	buffer.memory = win.VirtualAlloc(nil, bitmap_memory_size, win.MEM_COMMIT | win.MEM_RESERVE, win.PAGE_READWRITE)

	buffer.pitch = width * buffer.bytes_per_pixel
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


win32_update_window :: proc(
	device_context: win.HDC,
	window_width, window_height: i32,
	buffer: Game_Backbuffer,
) {
	info := buffer.info

	win.StretchDIBits(
		device_context,
		0,
		0,
		buffer.width,
		buffer.height,
		0,
		0,
		buffer.width,
		buffer.height,
		buffer.memory,
		&info,
		win.DIB_RGB_COLORS,
		win.SRCCOPY,
	)
}


win32_get_wall_clock :: proc() -> win.LARGE_INTEGER{
	result : win.LARGE_INTEGER
	win.QueryPerformanceCounter(&result)
	return result
}

win32_get_seconds_elapsed :: proc(start, end : win.LARGE_INTEGER) -> f32{
	result := (transmute(f64)end - transmute(f64)start) / f64(global_perf_count_frequency) 

	return f32(result)
}

win32_get_input_file_location :: proc(p_state : ^Win32_State, slot_index : int, dest_count : int, dest : u8){
	assert(slot_index == 1)

}

round_real32_to_int32 :: proc(p_number : f32) -> i32{
	result := i32(p_number +0.5)
	return result
}

draw_rectangle :: proc(p_buffer : ^Game_Backbuffer, p_real_min_x, p_real_min_y, p_real_max_x, p_real_max_y : f32, p_color : u32){
	min_x := round_real32_to_int32(p_real_min_x)
	min_y := round_real32_to_int32(p_real_min_y)
	max_x := round_real32_to_int32(p_real_max_x)
	max_y := round_real32_to_int32(p_real_max_y)

	pixel := ([^]u32)(p_buffer.memory)

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

			pixel[y_bit * p_buffer.width + x_bit] = p_color
		}
	}
}

