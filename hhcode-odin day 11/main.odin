package handmade

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

global_running: bool
global_backbuffer: Game_Backbuffer

//i found there was a lot of typedef and define junk when dealing with c in this tutorial,
// these next 4 lines work just fine for now

XInputGetState :: #type proc(dw_user_index: win.DWORD, p_state: ^xpt.XINPUT_STATE)
XInputSetState :: #type proc(dw_user_index: win.DWORD, p_vibration: ^xpt.XINPUT_VIBRATION)

xpt_get_state: ^XInputGetState
xpt_set_state: ^XInputSetState

global_wfx: win.WAVEFORMATEX
global_source_voice: ^xaudio2.IXAudio2SourceVoice

global_x_offset: i32
global_y_offset: i32

main :: proc() {
	perf_count_frequency_result : win.LARGE_INTEGER
	win.QueryPerformanceFrequency(&perf_count_frequency_result)
	perf_count_frequency := transmute(f64)perf_count_frequency_result
	last_counter : win.LARGE_INTEGER 
	win.QueryPerformanceCounter(&last_counter)

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

	for global_running {
		message: win.MSG

		for win.PeekMessageW(&message, nil, 0, 0, win.PM_REMOVE) {

			if message.message == win.WM_QUIT {
				global_running = false
			}

			win.TranslateMessage(&message)
			win.DispatchMessageW(&message)
		}

        win32_update_xinput()

		//render_weird_gradient(global_backbuffer, global_x_offset, global_y_offset)

		dimension := win32_get_window_dimension(window)

		win32_display_buffer_in_window(
			device_context,
			dimension.width,
			dimension.height,
			global_backbuffer,
		)

		main_loop()

		global_x_offset += 1
		global_y_offset += 2

		end_counter : win.LARGE_INTEGER
		win.QueryPerformanceCounter(&end_counter)

		end_cycle_count := f64(intrinsics.read_cycle_counter())

		counter_elapsed := transmute(f64)end_counter - transmute(f64)last_counter
		cycles_elapsed := end_cycle_count - last_cycle_count

		ms_per_frame := (1000*counter_elapsed) / perf_count_frequency
		fps := perf_count_frequency / counter_elapsed
		last_counter = end_counter

		last_cycle_count = end_cycle_count
		mega_cycles_per_frame := cycles_elapsed / (1000 * 1000)

		fps_buffer : [32]byte
		fps_slice := fmt.bprintf(fps_buffer[:], "fps: %f ", fps)

		ms_per_frame_buffer : [32]byte
		ms_per_frame_slice := fmt.bprintf(ms_per_frame_buffer[:], "ms_per_frame: %f", ms_per_frame)

		mega_cycles_buffer : [32]byte
		mega_cycles_slice := fmt.bprintf(mega_cycles_buffer[:], " mega cycles: %f", mega_cycles_per_frame)

		fps_val := string(fps_slice)
		ms_per_frame_val := string(ms_per_frame_slice)
		mega_cycles_val := string(mega_cycles_slice)

		str_val := strings.concatenate({fps_val, ms_per_frame_val, mega_cycles_val})
		fmt.println(str_val)
		}
}

main_loop :: proc(){
	game_update_and_render(&global_backbuffer)
}

game_update_and_render :: proc(game_offscreen_buffer: ^Game_Backbuffer){
	render_weird_gradient(game_offscreen_buffer, global_x_offset, global_y_offset)
}

win32_load_xinput :: proc(){
    x_input_library : win.HMODULE = win.LoadLibraryW("Xinput1_3.dll")
    if x_input_library != nil{
        //need to use cast() here, the call style type_to_cast(something_getting_cast) doesnt work
        xpt_get_state = cast(^XInputGetState)(win.GetProcAddress(x_input_library, "XInputGetState"))
        xpt_set_state = cast(^XInputSetState)(win.GetProcAddress(x_input_library, "XInputSetState"))
    }else{
        fmt.println("cannot load xinput")
    }
}

win32_update_xinput :: proc(){
controller_index: xpt.XUSER = xpt.XUSER(0)
        pad_state: xpt.XINPUT_STATE

        if xpt.XInputGetState(controller_index, &pad_state) == win.System_Error(win.ERROR_SUCCESS){
            fmt.println("controller connected")

            up: bool = .DPAD_UP in pad_state.Gamepad.wButtons
            down: bool = .DPAD_DOWN in pad_state.Gamepad.wButtons
            left: bool = .DPAD_LEFT in pad_state.Gamepad.wButtons
            right: bool = .DPAD_RIGHT in pad_state.Gamepad.wButtons
            start: bool = .START in pad_state.Gamepad.wButtons
            back: bool = .BACK in pad_state.Gamepad.wButtons
            right_shoulder: bool = .RIGHT_SHOULDER in pad_state.Gamepad.wButtons
            left_shoulder: bool = .LEFT_SHOULDER in pad_state.Gamepad.wButtons
            a: bool = .A in pad_state.Gamepad.wButtons
            b: bool = .B in pad_state.Gamepad.wButtons
            x: bool = .X in pad_state.Gamepad.wButtons
            y: bool = .Y in pad_state.Gamepad.wButtons

            stick_x: i16 = pad_state.Gamepad.sThumbLX
            stick_y: i16 = pad_state.Gamepad.sThumbLY

            global_x_offset += i32(stick_x) >> 12
            global_y_offset += i32(stick_y) >> 12
            
        }else{
            
        }

        vibration: xpt.XINPUT_VIBRATION
        vibration.wLeftMotorSpeed = 60000
        vibration.wRightMotorSpeed = 60000
        xpt.XInputSetState(controller_index, &vibration)

}

win32_init_xaudio :: proc(){
    result := win.CoInitializeEx(nil, win.COINIT.MULTITHREADED)
    if win.FAILED(result){
        fmt.println("error initializing com")
        return
    }
    defer win.CoInitialize()

    x2_object: ^xaudio2.IXAudio2
    result = xaudio2.Create(&x2_object, nil, xaudio2.USE_DEFAULT_PROCESSOR)
    if win.FAILED(result){
        fmt.println("failed to create xaudio engine")
        return
    }

    master_voice: ^xaudio2.IXAudio2MasteringVoice
    result = x2_object.CreateMasteringVoice(x2_object, &master_voice, xaudio2.DEFAULT_CHANNELS, 
                                            xaudio2.DEFAULT_SAMPLERATE, nil, nil, nil, .Other)
    if win.FAILED(result){
        fmt.println("failed to create mastering voice")
        return
    }

    fmt.println("xaudio initialized successfully")

	global_wfx = {
		wFormatTag = win.WAVE_FORMAT_PCM,
		nChannels = 2,
		nSamplesPerSec = 44100,
		nAvgBytesPerSec = 44100 * 2 * 2,
		nBlockAlign = 2 * 2,
		wBitsPerSample = 16,
		cbSize = 0,
	}


	result = x2_object.CreateSourceVoice(x2_object, &global_source_voice, &global_wfx, nil, xaudio2.DEFAULT_FREQ_RATIO, nil, nil, nil)
	if win.FAILED(result){
		fmt.println("failed to create soource voice")
	}

	sample_rate :: 44100
	duration :: 1.0
	total_samples :: sample_rate * duration
	frequency :: 390.0

	raw_pcm_data := make([]u8, int(total_samples))

	for i in 0..<int(total_samples){
		t := f64(i) / f64(sample_rate)
		sample_val := math.sin(2.0 * math.PI * frequency * t)
		raw_pcm_data[i] = u8(sample_val * 32767.0)
	}

	audio_buffer: xaudio2.BUFFER = {
		Flags = {.END_OF_STREAM},
		AudioBytes = u32(len(raw_pcm_data)),
		pAudioData = raw_data(raw_pcm_data),
	}

	result = global_source_voice.SubmitSourceBuffer(global_source_voice, &audio_buffer, nil)
	if win.FAILED(result){
		fmt.println("failed to submit source buffer")
		return
	}

	result = global_source_voice.Start(global_source_voice, nil, 0)
	if win.FAILED(result){
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

		case win.WM_DESTROY:
			global_running = false

		case win.WM_SYSKEYDOWN:
			fallthrough
		case win.WM_SYSKEYUP:
			fallthrough
		case win.WM_KEYDOWN:
			fallthrough
		case win.WM_KEYUP:
			is_down: bool = ((lparam & (1 << 31)) == 0)
			was_down: bool = ((lparam & (1 << 30)) != 0)
			alt_key_was_down : bool = ((lparam & (1 << 29)) != 0)

			//vkcode: win.WPARAM does not work
			vk_code := u32(wparam) & 0xFFFF //masks any unintended higher bits
			if is_down != was_down{
				switch vk_code{
					case 'W':
						fmt.println("w pressed switch")
					case 'A':
					case 'S':
					case 'D':
					case 'Q':
					case 'E':
					case win.VK_UP:
					case win.VK_DOWN:
					case win.VK_LEFT:
					case win.VK_RIGHT:
					case win.VK_ESCAPE:
						if is_down{
							fmt.println("escape is down")
						}
						if was_down{
							fmt.println("escape was down")
						}
					case win.VK_SPACE:
					case win.VK_F4:
						if alt_key_was_down{
							global_running = false
						}
				}
			}
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