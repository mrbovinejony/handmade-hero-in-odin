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
