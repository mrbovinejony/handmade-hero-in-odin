package handmade

import "base:intrinsics"
import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
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
	game_memory: Game_Memory
	game_memory.permanent_storage_size = megabytes(64)
	game_memory.transient_storage_size = gigabytes(64)
	game_memory.permanent_storage = win.VirtualAlloc(
		nil,
		uint(game_memory.permanent_storage_size),
		win.MEM_RESERVE | win.MEM_COMMIT,
		win.PAGE_READWRITE,
	)
	game_memory.transient_storage = win.VirtualAlloc(
		nil,
		uint(game_memory.transient_storage_size),
		win.MEM_RESERVE | win.MEM_COMMIT,
		win.PAGE_READWRITE,
	)

	game_input: [2]Game_Input
	old_input := &game_input[0]
	new_input := &game_input[1]

	perf_count_frequency_result: win.LARGE_INTEGER
	win.QueryPerformanceFrequency(&perf_count_frequency_result)
	global_perf_count_frequency = transmute(f64)perf_count_frequency_result
	perf_count_frequency := transmute(f64)perf_count_frequency_result
	last_counter := win32_get_wall_clock()

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

	monitor_refresh_hz : int = 60
	game_update_hz := monitor_refresh_hz/2
	target_second_per_frame : f32 = 1.0/ f32(game_update_hz)

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
			win32_process_pending_messages(new_keyboard_controller)

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

			
			fps := 0.0

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
			fmt.println(str_val)


		}
	}
}

win32_process_pending_messages :: proc(p_keyboard_controller : ^Game_Controller_Input) {
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
					fmt.println("keyboard w move up")
				case 'A':
					win32_process_keyboard_message(&p_keyboard_controller.move_left, is_down)
					fmt.println("keyboard a move left")
				case 'S':
					win32_process_keyboard_message(&p_keyboard_controller.move_down, is_down)
					fmt.println("keyboard s move down")
				case 'D':
					win32_process_keyboard_message(&p_keyboard_controller.move_right, is_down)
					fmt.println("keyboard d move right")
				case 'Q':
					win32_process_keyboard_message(&p_keyboard_controller.left_shoulder, is_down)
					fmt.println("keyboard q left shoulder")
				case 'E':
					win32_process_keyboard_message(&p_keyboard_controller.right_shoulder, is_down)
					fmt.println("keyboard e right shoulder")
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

main_loop :: proc() {
	//game_update_and_render(&global_backbuffer, &global_game_input)
}

game_update_and_render :: proc(p_game_memory: ^Game_Memory, p_game_offscreen_buffer: ^Game_Backbuffer, p_game_input: ^Game_Input) {
	//assert((&p_game_input.controllers[0].terminator - &p_game_input.controllers[0].buttons[0]) == (len(p_game_input.controllers[0].buttons)))
	game_state := (^Game_State)(p_game_memory.permanent_storage)
	assert(size_of(Game_State) <= p_game_memory.permanent_storage_size)

	if p_game_memory.is_initialized == false {
		game_state.x_offset = 0
		game_state.y_offset = 0
		p_game_memory.is_initialized = true
	}
	delta : i32= 5

		controller_input := p_game_input.controllers[0]
		if controller_input.move_up.ended_down{
			game_state.y_offset += delta
			fmt.println("move up")
		}
		if controller_input.move_down.ended_down{
			game_state.y_offset -= delta
		}
		if controller_input.move_left.ended_down{
			game_state.x_offset -= delta
		}
		if controller_input.move_right.ended_down{
			game_state.x_offset += delta
		}
	
	render_weird_gradient(p_game_offscreen_buffer, game_state.x_offset, game_state.y_offset)
}

win32_load_xinput :: proc() {
	x_input_library: win.HMODULE = win.LoadLibraryW("Xinput1_3.dll")
	if x_input_library != nil {
		//need to use cast() here, the call style type_to_cast(something_getting_cast) doesnt work
		xpt_get_state = cast(^XInputGetState)(win.GetProcAddress(
				x_input_library,
				"XInputGetState",
			))
		xpt_set_state = cast(^XInputSetState)(win.GetProcAddress(
				x_input_library,
				"XInputSetState",
			))
	} else {
		fmt.println("cannot load xinput")
	}
}

win32_process_keyboard_message :: proc(p_new_state : ^Game_Button_State, p_is_down : bool){
	assert(p_new_state.ended_down != p_is_down, "state not equal")

	p_new_state.ended_down = p_is_down
	p_new_state.half_transition_count += 1

	if p_new_state.ended_down{
		fmt.println(p_new_state)
	}
}

win32_process_xinput_digital_button :: proc(
	new_state, old_state: ^Game_Button_State,
	button_state: win.XINPUT_GAMEPAD_BUTTON, button_bit: win.XINPUT_GAMEPAD_BUTTON_BIT,
) {
	new_state.ended_down = button_bit in button_state
	new_state.half_transition_count = (old_state.ended_down != new_state.ended_down) ? 1 : 0
	
	if new_state.ended_down{
		fmt.println(button_state)
	}
}

win32_process_x_input_stick_value :: proc(p_val : win.SHORT, p_dead_zone_threshold : win.SHORT) -> f32{
	result : f32

	if p_val < -p_dead_zone_threshold{
		result = (f32(p_val) + f32(p_dead_zone_threshold)) / (f32(32768.0) - f32(p_dead_zone_threshold))
		fmt.println(result)
	}
	else if p_val > p_dead_zone_threshold{
		result = (f32(p_val) - f32(p_dead_zone_threshold)) / (f32(32767.0) - f32(p_dead_zone_threshold))
		fmt.println(result)
	}

	return result
}

win32_update_xinput :: proc(old_input, new_input: ^Game_Input) {
	max_controller_count := win.XUSER_MAX_COUNT

	if max_controller_count > (len(global_game_input.controllers) - 1) {
		max_controller_count = len(global_game_input.controllers) - 1
	}

	for i := 0; i < max_controller_count; i += 1 {
		state: win.XINPUT_STATE

		old_controller := &old_input.controllers[i + 1]
		new_controller := &new_input.controllers[i + 1]


		if win.XInputGetState(cast(win.XUSER)i, &state) == win.System_Error(win.ERROR_SUCCESS) {
			new_controller.is_connected = true
			new_controller.is_analog = true

			gamepad_state := state.Gamepad

			//controller.down is the bottom button on the controller, xbox is a ps4 is x, dpad will be dpad_down
			win32_process_xinput_digital_button(&new_controller.action_down, &old_controller.action_down, gamepad_state.wButtons, .A)
			win32_process_xinput_digital_button(&new_controller.action_left, &old_controller.action_left, gamepad_state.wButtons, .X)
			win32_process_xinput_digital_button(&new_controller.action_right, &old_controller.action_right, gamepad_state.wButtons, .B)
			win32_process_xinput_digital_button(&new_controller.action_up, &old_controller.action_up, gamepad_state.wButtons, .Y)
			win32_process_xinput_digital_button(&new_controller.left_shoulder, &old_controller.left_shoulder, gamepad_state.wButtons, .LEFT_SHOULDER)
			win32_process_xinput_digital_button(&new_controller.right_shoulder, &old_controller.right_shoulder, gamepad_state.wButtons, .RIGHT_SHOULDER)
			win32_process_xinput_digital_button(&new_controller.start, &old_controller.start, gamepad_state.wButtons, .START)
			win32_process_xinput_digital_button(&new_controller.back, &old_controller.back, gamepad_state.wButtons, .BACK)

			new_controller.stick_average_x = win32_process_x_input_stick_value(gamepad_state.sThumbLX, win.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
			new_controller.stick_average_y = win32_process_x_input_stick_value(gamepad_state.sThumbLY, win.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)

			if new_controller.stick_average_x != 0.0 || new_controller.stick_average_y != 0{
				new_controller.is_analog = true
				fmt.println("analog")
			}

			if .DPAD_UP in gamepad_state.wButtons{
				new_controller.stick_average_y = 1.0
				new_controller.is_analog = false
				fmt.println("dpad up")
			}
			if .DPAD_DOWN in gamepad_state.wButtons{
				new_controller.stick_average_y = -1.0
				new_controller.is_analog = false
				fmt.println("dpad down")
			}
			if .DPAD_LEFT in gamepad_state.wButtons{
				new_controller.stick_average_x = -1.0
				new_controller.is_analog = false
				fmt.println("dpad left")
			}
			if .DPAD_RIGHT in gamepad_state.wButtons{
				new_controller.stick_average_x = 1.0
				new_controller.is_analog = false
				fmt.println("dpad right")
			}

			threshold : f32 = 0.5

			win32_process_xinput_digital_button(&new_controller.move_right, &old_controller.move_right, gamepad_state.wButtons, win.XINPUT_GAMEPAD_BUTTON_BIT(1))
			win32_process_xinput_digital_button(&new_controller.move_left, &old_controller.move_left,gamepad_state.wButtons, win.XINPUT_GAMEPAD_BUTTON_BIT(1))
			win32_process_xinput_digital_button(&new_controller.move_up, &old_controller.move_up, gamepad_state.wButtons, win.XINPUT_GAMEPAD_BUTTON_BIT(1))
			win32_process_xinput_digital_button(&new_controller.move_down, &old_controller.move_down, gamepad_state.wButtons, win.XINPUT_GAMEPAD_BUTTON_BIT(1))

			vibration: win.XINPUT_VIBRATION
			vibration.wLeftMotorSpeed = 60000
			vibration.wRightMotorSpeed = 60000
			//win.XInputSetState(win.XUSER(i), &vibration)
		}else{
			new_controller.is_connected = false
		}
	}
}

win32_init_xaudio :: proc() {
	result := win.CoInitializeEx(nil, win.COINIT.MULTITHREADED)
	if win.FAILED(result) {
		fmt.println("error initializing com")
		return
	}
	defer win.CoInitialize()

	x2_object: ^xaudio2.IXAudio2
	result = xaudio2.Create(&x2_object, nil, xaudio2.USE_DEFAULT_PROCESSOR)
	if win.FAILED(result) {
		fmt.println("failed to create xaudio engine")
		return
	}

	master_voice: ^xaudio2.IXAudio2MasteringVoice
	result = x2_object.CreateMasteringVoice(
		x2_object,
		&master_voice,
		xaudio2.DEFAULT_CHANNELS,
		xaudio2.DEFAULT_SAMPLERATE,
		nil,
		nil,
		nil,
		.Other,
	)
	if win.FAILED(result) {
		fmt.println("failed to create mastering voice")
		return
	}

	fmt.println("xaudio initialized successfully")

	global_wfx = {
		wFormatTag      = win.WAVE_FORMAT_PCM,
		nChannels       = 2,
		nSamplesPerSec  = 44100,
		nAvgBytesPerSec = 44100 * 2 * 2,
		nBlockAlign     = 2 * 2,
		wBitsPerSample  = 16,
		cbSize          = 0,
	}


	result = x2_object.CreateSourceVoice(
		x2_object,
		&global_source_voice,
		&global_wfx,
		nil,
		xaudio2.DEFAULT_FREQ_RATIO,
		nil,
		nil,
		nil,
	)
	if win.FAILED(result) {
		fmt.println("failed to create soource voice")
	}

	sample_rate :: 44100
	duration :: 1.0
	total_samples :: sample_rate * duration
	frequency :: 390.0

	raw_pcm_data := make([]u8, int(total_samples))

	for i in 0 ..< int(total_samples) {
		t := f64(i) / f64(sample_rate)
		sample_val := math.sin(2.0 * math.PI * frequency * t)
		raw_pcm_data[i] = u8(sample_val * 32767.0)
	}

	audio_buffer: xaudio2.BUFFER = {
		Flags      = {.END_OF_STREAM},
		AudioBytes = u32(len(raw_pcm_data)),
		pAudioData = raw_data(raw_pcm_data),
	}

	result = global_source_voice.SubmitSourceBuffer(global_source_voice, &audio_buffer, nil)
	if win.FAILED(result) {
		fmt.println("failed to submit source buffer")
		return
	}

	result = global_source_voice.Start(global_source_voice, nil, 0)
	if win.FAILED(result) {
		fmt.println("failed to start playback")
		return
	}
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

debug_platform_read_entire_file :: proc(p_filename: cstring16) -> Debug_Read_File_Result {
	result: Debug_Read_File_Result

	file_handle := win.CreateFileW(
		p_filename,
		win.GENERIC_READ,
		win.FILE_SHARE_READ,
		nil,
		win.OPEN_EXISTING,
		0,
		nil,
	)

	if file_handle != win.INVALID_HANDLE_VALUE {
		file_size: win.LARGE_INTEGER
		if win.GetFileSizeEx(file_handle, &file_size) {
			result.contents = win.VirtualAlloc(
				nil,
				uint(file_size),
				win.MEM_RESERVE | win.MEM_COMMIT,
				win.PAGE_READWRITE,
			)
			if result.contents != nil {
				bytes_read: win.DWORD
				if win.ReadFile(file_handle, result.contents, u32(file_size), &bytes_read, nil) &&
				   u32(file_size) == bytes_read {
					result.contents_size = bytes_read
				} else {
					fmt.println("file read failed")
					debug_platform_free_file_memory(result.contents)
					result.contents = nil
					return result
				}
			} else {
				fmt.println("memory allocation failed")
			}
		} else {
			fmt.println("cant get file size")
		}
	} else {
		fmt.println("file handle not created")
	}

	return result
}
debug_platform_free_file_memory :: proc(p_memory: rawptr) {
	if p_memory != nil {
		win.VirtualFree(p_memory, 0, win.MEM_RELEASE)
	}
}
debug_platform_write_entire_file :: proc(
	p_filename: cstring16,
	p_memory_size: u32,
	p_memory: rawptr,
) -> bool {
	result: bool

	file_handle := win.CreateFileW(
		p_filename,
		win.GENERIC_WRITE,
		0,
		nil,
		win.CREATE_ALWAYS,
		0,
		nil,
	)

	if file_handle != win.INVALID_HANDLE_VALUE {
		bytes_written: win.DWORD
		if win.WriteFile(file_handle, p_memory, p_memory_size, &bytes_written, nil) {
			result = (bytes_written == p_memory_size)
		} else {
			fmt.println("write failed")
		}
		win.CloseHandle(file_handle)
	} else {
		fmt.println("handle creation failed")
	}
	return result
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
