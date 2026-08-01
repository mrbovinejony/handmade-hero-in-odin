package handmade

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

debug_begin_recording_input :: proc(p_state : ^Win32_State, p_input_recording_index : i32){
	fmt.println("begin recording input")
	p_state.input_recording_index = p_input_recording_index

	filename : cstring16 = "foo.hmi"
	p_state.recording_handle = win.CreateFileW(filename, win.GENERIC_WRITE, 0, nil, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, nil)
	if p_state.recording_handle == win.INVALID_HANDLE_VALUE{
		fmt.println("begin recording input: failed to make file")
	}

	bytes_written : win.DWORD
	assert(p_state.total_size <= 0xFFFFFFFF)
	bytes_to_write := u32(p_state.total_size)
	win.WriteFile(p_state.recording_handle, p_state.game_memory_block, bytes_to_write, &bytes_written, nil)
}

debug_record_input :: proc(p_state : ^Win32_State, p_input : ^Game_Input){
	bytes_written : win.DWORD

	if win.WriteFile(p_state.recording_handle, p_input, size_of(p_input), &bytes_written, nil) == true{
		fmt.println("record_input: recording")
	}else{
		fmt.println("record_input: cant record")
	}
}

debug_end_recording_input :: proc(p_state : ^Win32_State){
	fmt.println("end recording input")
	win.CloseHandle(p_state.recording_handle)
	p_state.input_recording_index = 0

}

debug_begin_input_playback :: proc(p_state : ^ Win32_State, p_input_playback_index : i32){
	fmt.println("begin input playback")
	p_state.input_playback_index = p_input_playback_index
	filename : cstring16 = "foo.hmi"

	p_state.playback_handle = win.CreateFileW(filename, win.GENERIC_READ, 0, nil, win.OPEN_EXISTING, 0, nil)
	if p_state.playback_handle == win.INVALID_HANDLE_VALUE{
		fmt.println("begin input playback: failed to make playback handle")
	}else{
		fmt.println("begin input playback: made playback handle")
	}

	bytes_read : win.DWORD
	win.ReadFile(p_state.playback_handle, p_state.game_memory_block, u32(p_state.total_size), &bytes_read, nil)
	assert(bytes_read == u32(p_state.total_size))
}

win32_playback_input :: proc(p_state : ^Win32_State, p_input : ^Game_Input){
	fmt.println("playback input")
	bytes_read : win.DWORD 

	if(win.ReadFile(p_state.playback_handle, p_input, size_of(p_input), &bytes_read, nil)){
		if bytes_read == 0{
			fmt.println("repeat playback")
			playing_index := p_state.input_playback_index
			debug_end_input_playback(p_state)
			debug_begin_input_playback(p_state, playing_index)
			if win.ReadFile(p_state.playback_handle, p_input, size_of(p_input), &bytes_read, nil) == true{
				fmt.println("playback_input: repeat readfile successful")
			}else{
				fmt.println("playback_input: repeat read file failed")
			}
		}
					assert(bytes_read == size_of(p_input))
	}
}

debug_end_input_playback :: proc(p_state : ^Win32_State){
	fmt.println("end input playback")
	win.CloseHandle(p_state.playback_handle)
	p_state.input_playback_index = 0
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