package handmade

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
			old_keyboard_controller : ^Game_Controller_Input = &old_input.controllers[0]
			new_keyboard_controller : ^Game_Controller_Input = &new_input.controllers[0]
			new_keyboard_controller^ = {}

			new_keyboard_controller.is_connected = true

			for i := 0; i < len(new_keyboard_controller.buttons); i += 1{
				new_keyboard_controller.buttons[i].ended_down = old_keyboard_controller.buttons[i].ended_down
			}
			win32_process_pending_messages(new_keyboard_controller, &win32_state)

			if win32_state.input_recording_index != 0{
				win32_record_input(&win32_state, new_input)
			}
			if win32_state.input_playback_index != 0{
				win32_playback_input(&win32_state, new_input)
			}

			game_update_and_render(&game_memory, &global_backbuffer, new_input)
			win32_update_xinput(old_input, new_input)

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
			win32_display_buffer_in_window(
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


/*win32_record_input :: proc(p_state : ^Win32_State, p_input : ^Game_Input){
	bytes_to_write := size_of(Game_Input)
	data := ([^]u8)(p_input)[:bytes_to_write]

	bytes_written, err := os.write(p_state.recording_handle, data)
	if err != os.ERROR_NONE{
		fmt.println("error recording input")
	}

	fmt.println("recording input")
}

win32_begin_recording_input :: proc(p_state : ^Win32_State, p_input_recording_index : i32){
	fmt.println("begin recording input")
	p_state.input_recording_index = p_input_recording_index

	handle, err := os.open("output.hmi", os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
	if err != os.ERROR_NONE{
		fmt.println("error creating recording handle")
	}

	p_state.recording_handle = handle
}

win32_end_recording_input :: proc(p_state : ^Win32_State){
	fmt.println("end recording input")
	os.close(p_state.recording_handle)
	p_state.input_recording_index = 0
}

win32_begin_input_playback :: proc(p_state : ^Win32_State, p_input_playback_index : i32){
	fmt.println("begin input playback")
	p_state.input_playback_index = p_input_playback_index

	handle, err := os.open("output.hmi", os.File_Flags{.Read})
	if err != os.ERROR_NONE{
		fmt.println("error creating player handle")
	}

	p_state.playback_handle = handle
}

win32_end_input_playbck :: proc(p_state : ^Win32_State){
	fmt.println("end input playback")
	os.close(p_state.playback_handle)
	p_state.input_playback_index = 0
}

win32_playback_input :: proc(p_state : ^Win32_State, p_input : ^Game_Input){
	fmt.println("playback input")

	bytes_read, read_err := os.read_ptr(p_state.playback_handle, p_input, size_of(p_input))
	if read_err != os.ERROR_NONE{
		fmt.println(read_err)
	}
}*/

win32_record_input :: proc(p_state : ^Win32_State, p_input : ^Game_Input){
	fmt.println(p_state.recording_handle)
	bytes_written : win.DWORD

	if win.WriteFile(p_state.recording_handle, p_input, size_of(p_input), &bytes_written, nil) == true{
		fmt.println("record_input: recording")
	}else{
		fmt.println("record_input: cant record")
	}
}

win32_begin_recording_input :: proc(p_state : ^Win32_State, p_input_recording_index : i32){
	fmt.println("begin recording input")
	p_state.input_recording_index = p_input_recording_index

	filename : cstring16 = "foo.hmi"
	p_state.recording_handle = win.CreateFileW(filename, win.GENERIC_WRITE, 0, nil, win.CREATE_ALWAYS, 0, nil)
	if p_state.recording_handle == win.INVALID_HANDLE_VALUE{
		fmt.println("begin recording input: failed to make file")
	}

	bytes_written : win.DWORD
	assert(p_state.total_size <= 0xFFFFFFFF)
	bytes_to_write := u32(p_state.total_size)
	win.WriteFile(p_state.recording_handle, p_state.game_memory_block, bytes_to_write, &bytes_written, nil)
}

win32_end_recording_input :: proc(p_state : ^Win32_State){
	fmt.println("end recording input")
	win.CloseHandle(p_state.recording_handle)
	p_state.input_recording_index = 0

}

win32_begin_input_playback :: proc(p_state : ^ Win32_State, p_input_playback_index : i32){
	fmt.println("begin input playback")
	p_state.input_playback_index = p_input_playback_index
	filename : cstring16 = "foo.hmi"

	p_state.playback_handle = win.CreateFileW(filename, win.GENERIC_READ, win.FILE_SHARE_READ, nil, win.OPEN_EXISTING, 0, nil)
	if p_state.playback_handle == win.INVALID_HANDLE_VALUE{
		fmt.println("begin input playback: failed to make playback handle")
	}else{
		fmt.println("begin input playback: made playback handle")
	}

	bytes_to_write := win.DWORD(p_state.total_size)
	bytes_read : win.DWORD
	win.ReadFile(p_state.playback_handle, p_state.game_memory_block, bytes_to_write, &bytes_read, nil)
	assert(u32(p_state.total_size) == bytes_read)
}

win32_end_input_playback :: proc(p_state : ^Win32_State){
	fmt.println("end input playback")
	win.CloseHandle(p_state.playback_handle)
	p_state.input_playback_index = 0
}

win32_playback_input :: proc(p_state : ^Win32_State, p_input : ^Game_Input){
	fmt.println("playback input")
	bytes_read : win.DWORD 

	if(win.ReadFile(p_state.playback_handle, p_input, size_of(p_input), &bytes_read, nil)){
		if bytes_read == 0{
			fmt.println("repeat playback")
			playing_index := p_state.input_playback_index
			win32_end_input_playback(p_state)
			win32_begin_input_playback(p_state, playing_index)
			if win.ReadFile(p_state.playback_handle, p_input, size_of(p_input), &bytes_read, nil) == true{
				fmt.println("playback_input: repeat readfile successful")
			}else{
				fmt.println("playback_input: repeat read file failed")
			}
			assert(bytes_read == size_of(p_input))
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
							win32_begin_recording_input(p_state, 1)
						}else{
							win32_end_recording_input(p_state)
							win32_begin_input_playback(p_state, 1)
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

game_update_and_render :: proc(p_game_memory: ^Game_Memory, p_game_offscreen_buffer: ^Game_Backbuffer, p_game_input: ^Game_Input) {
	//assert((&p_game_input.controllers[0].terminator - &p_game_input.controllers[0].buttons[0]) == (len(p_game_input.controllers[0].buttons)))
	game_state := (^Game_State)(p_game_memory.permanent_storage)
	assert(size_of(Game_State) <= p_game_memory.permanent_storage_size)

	if p_game_memory.is_initialized == false {
		game_state.x_offset = 0
		game_state.y_offset = 0
		game_state.player_x = 100
		game_state.player_y = 100
		p_game_memory.is_initialized = true
	}
	delta : i32= 5

	for i := 0; i < len(p_game_input.controllers); i +=1{
			controller_input := p_game_input.controllers[i]
			if controller_input.move_up.ended_down{
				game_state.player_y -= delta
			}
			if controller_input.move_down.ended_down{
				game_state.player_y += delta
			}
			if controller_input.move_left.ended_down{
				game_state.player_x -= delta
			}
			if controller_input.move_right.ended_down{
				game_state.player_x += delta
			}

			game_state.player_x += i32(4.0 * controller_input.stick_average_x)
			game_state.player_y -= i32(4.0 * controller_input.stick_average_y)
			game_state.player_y -= i32(4.0 * controller_input.stick_average_y)
			
			if controller_input.action_down.ended_down{
				game_state.t_jump = f32(2.0 * math.PI)
			}
			if game_state.t_jump > 0{
				game_state.player_x += 5
				game_state.player_y += i32(math.sin(game_state.t_jump) * 20)
				game_state.t_jump -= 0.2
			}
			game_state.t_jump -= 0.033
		}



	render_weird_gradient(p_game_offscreen_buffer, game_state.x_offset, game_state.y_offset)
		render_player(p_game_offscreen_buffer, game_state.player_x, game_state.player_y)
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

			win32_display_buffer_in_window(
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
			biSize = size_of(win.BITMAPINFOHEADER),
			biWidth = buffer.width,
			biHeight = -buffer.height,
			biPlanes = 1,
			biBitCount = 32,
			biCompression = win.BI_RGB,
		},
	}

	bitmap_memory_size := uint(buffer.width * buffer.height * buffer.bytes_per_pixel)
	buffer.memory = win.VirtualAlloc(nil, bitmap_memory_size, win.MEM_COMMIT, win.PAGE_READWRITE)

	buffer.pitch = width * buffer.bytes_per_pixel
}

render_weird_gradient :: proc(buffer: ^Game_Backbuffer, blue_offset, green_offset: i32) {
	pixel := ([^]u32)(buffer.memory)

	for y in 0 ..< buffer.height {
		for x in 0 ..< buffer.width {
			blue := u8(x + blue_offset)
			green := u8(y + green_offset)

			pixel[y * buffer.width + x] = (u32(green) << 8) | u32(blue)
		}
	}
}

render_player :: proc(p_buffer: ^Game_Backbuffer, p_player_x, p_player_y: i32) {
	pixel := ([^]u32)(p_buffer.memory)

	color := 0xFFFFFFFF
	left := p_player_x
	top := p_player_y
	right := p_player_x + 10
	bottom := p_player_y + 10

	x, y : i32

	for x = left; x < right; x += 1{
		for y = top; y < bottom; y += 1{
			x_bit := (x + p_player_x)
			y_bit := (y + p_player_y)

			pixel[y_bit * p_buffer.width + x_bit] = u32(color)
		}
	}
}


win32_display_buffer_in_window :: proc(
	device_context: win.HDC,
	window_width, window_height: i32,
	buffer: Game_Backbuffer,
) {
	info := buffer.info

	win.StretchDIBits(
		device_context,
		0,
		0,
		window_width,
		window_height,
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
