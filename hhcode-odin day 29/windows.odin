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

win32_update_window :: proc(
	device_context: win.HDC,
	window_width, window_height: i32,
	buffer: Game_Backbuffer,
) {
	info := buffer.info
	offset_x := i32(10)
	offset_y := i32(10)

	win.PatBlt(device_context, 0, 0, window_width, window_height, win.BLACKNESS)
	win.PatBlt(device_context, 0, 0, window_width, offset_y, win.BLACKNESS)
	win.PatBlt(device_context, 0, offset_y + buffer.height, window_width, window_height, win.BLACKNESS)
	win.PatBlt(device_context, offset_x + buffer.width, 0, window_width, window_height, win.BLACKNESS)

	win.StretchDIBits(
		device_context,
		offset_x,
		offset_y,
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

round_real32_to_uint32 :: proc(p_number : f32) -> u32{
	result := u32(p_number + 0.5)
	return result
}

truncate_real32_to_int32 :: proc(p_number : f32) -> i32{
	result := i32(p_number)
	return result
}

truncate_real32_to_int :: proc(p_number : f32) -> int{
	result := int(p_number)
	return result
}
