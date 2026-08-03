package handmade

import "base:intrinsics"
import "base:runtime"
import "core:bufio"
import "core:fmt"
import img "core:image"
import "core:image/bmp"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:path/slashpath"
import "core:strings"
import win "core:sys/windows"
import "vendor:windows/GameInput"
import xaudio2 "vendor:windows/XAudio2"

global_running: bool
global_backbuffer: Game_Backbuffer
global_game_input: Game_Input
global_perf_count_frequency: f64

TILE_MAP_COUNT_X :: int
TILE_MAP_COUNT_Y :: int

bitmap1: ^bmp.Image
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
	win32_state: Win32_State

	game_memory: Game_Memory
	game_memory.permanent_storage_size = megabytes(64)
	game_memory.transient_storage_size = gigabytes(1)

	game_memory.transient_storage = win.VirtualAlloc(
		nil,
		uint(game_memory.transient_storage_size),
		win.MEM_RESERVE | win.MEM_COMMIT,
		win.PAGE_READWRITE,
	)

	win32_state.total_size =
		(game_memory.permanent_storage_size + game_memory.transient_storage_size)
	win32_state.game_memory_block = win.VirtualAlloc(
		nil,
		win.size_t(win32_state.total_size),
		win.MEM_RESERVE | win.MEM_COMMIT,
		win.PAGE_READWRITE,
	)

	game_memory.permanent_storage = win32_state.game_memory_block
	game_memory.transient_storage = rawptr(
		uintptr(game_memory.permanent_storage) + uintptr(game_memory.permanent_storage_size),
	)

	game_input: [2]Game_Input
	old_input := &game_input[0]
	new_input := &game_input[1]

	perf_count_frequency_result: win.LARGE_INTEGER
	win.QueryPerformanceFrequency(&perf_count_frequency_result)
	global_perf_count_frequency = transmute(f64)perf_count_frequency_result
	perf_count_frequency := transmute(f64)perf_count_frequency_result
	last_counter := win32_get_wall_clock()

	monitor_refresh_hz: int = 60
	game_update_hz := monitor_refresh_hz / 2
	target_second_per_frame: f32 = 1.0 / f32(game_update_hz)

	//equivalent to __rdtsc() need import "base:intrinsics"
	last_cycle_count := f64(intrinsics.read_cycle_counter())

	//win32_init_xaudio()
	win32_load_xinput()

	instance := win.HINSTANCE(win.GetModuleHandleW(nil))

	//1920 * 1080
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
	thread: Thread_Context

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

			old_keyboard_controller: ^Game_Controller_Input = &old_input.controllers[0]
			new_keyboard_controller: ^Game_Controller_Input = &new_input.controllers[0]
			new_keyboard_controller^ = {}
			new_keyboard_controller.is_connected = true

			for i := 0; i < len(new_keyboard_controller.buttons); i += 1 {
				new_keyboard_controller.buttons[i].ended_down =
					old_keyboard_controller.buttons[i].ended_down
			}

			win32_process_pending_messages(new_keyboard_controller, &win32_state)

			game_buffer: Game_Backbuffer
			game_buffer.memory = global_backbuffer.memory
			game_buffer.bytes_per_pixel = global_backbuffer.bytes_per_pixel
			game_buffer.width = global_backbuffer.width
			game_buffer.height = global_backbuffer.height
			game_buffer.pitch = game_buffer.width * game_buffer.bytes_per_pixel

			if win32_state.input_recording_index != 0 {
				debug_record_input(&win32_state, new_input)
			}
			if win32_state.input_playback_index != 0 {
				win32_playback_input(&win32_state, new_input)
			}

			point: win.POINT
			win.GetCursorPos(&point)
			//win.ScreenToClient(window, &point)
			new_input.mouse_x = point.x
			new_input.mouse_y = point.y

			new_input.mouse_buttons[0].ended_down =
				i32(win.GetKeyState(win.VK_LBUTTON)) & i32(1 << 15) != 0
			new_input.mouse_buttons[1].ended_down =
				i32(win.GetKeyState(win.VK_RBUTTON)) & i32(1 << 15) != 0
			new_input.mouse_buttons[2].ended_down =
				i32(win.GetKeyState(win.VK_MBUTTON)) & i32(1 << 15) != 0
			new_input.mouse_buttons[3].ended_down =
				i32(win.GetKeyState(win.VK_XBUTTON1)) & i32(1 << 15) != 0
			new_input.mouse_buttons[4].ended_down =
				i32(win.GetKeyState(win.VK_XBUTTON2)) & i32(1 << 15) != 0

			win32_update_xinput(old_input, new_input)
			game_update_and_render(&game_memory, &game_buffer, new_input)

			work_counter := win32_get_wall_clock()
			work_seconds_elapsed := win32_get_seconds_elapsed(last_counter, work_counter)

			seconds_elapsed_for_frame := work_seconds_elapsed

			desired_scheduler_ms: u32 = 1
			sleep_is_granular := (win.timeBeginPeriod(desired_scheduler_ms) == win.TIMERR_NOERROR)
			if seconds_elapsed_for_frame < target_second_per_frame {
				for seconds_elapsed_for_frame < target_second_per_frame {
					if sleep_is_granular {
						sleep_ms := win.DWORD(
							1000.0 * (target_second_per_frame - seconds_elapsed_for_frame),
						)
						if sleep_ms > 0 {
							win.Sleep(sleep_ms)
						}
					}
					seconds_elapsed_for_frame = win32_get_seconds_elapsed(
						last_counter,
						win32_get_wall_clock(),
					)
				}
			} else {
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
		}
	}
}

game_update_and_render :: proc(
	p_game_memory: ^Game_Memory,
	p_buffer: ^Game_Backbuffer,
	p_input: ^Game_Input,
) {
	//assert((&p_game_input.controllers[0].terminator - &p_game_input.controllers[0].buttons[0]) == (len(p_game_input.controllers[0].buttons)))
	game_state := (^Game_State)(p_game_memory.permanent_storage)
	assert(size_of(Game_State) <= p_game_memory.permanent_storage_size)

	player_height := f32(1.4)
	player_width := 0.75 * player_height

	if p_game_memory.is_initialized == false {
		p_game_memory.debug_read_entire_file = debug_platform_read_entire_file

		game_state.player_p.abs_tile_x = 3
		game_state.player_p.abs_tile_y = 3
		game_state.player_p.abs_tile_z = 0
		game_state.player_p.offset_x = 5.0
		game_state.player_p.offset_y = 5.0
		abs_tile_z := u32(0)

		buf: [50000]u8
		mem.arena_init(&game_state.world_arena, buf[:])
		allocator := mem.arena_allocator(&game_state.world_arena)

		world := new(World, allocator)
		game_state.world = world
		tile_map := new(Tile_Map, allocator)
		world.tile_map = tile_map

		game_state.backdrop = load_bitmap("data/test/test_background.bmp")
		game_state.hero_head = load_bitmap("data/test/test_hero_front_head.bmp")
		game_state.hero_cape = load_bitmap("data/test/test_hero_front_cape.bmp")
		game_state.hero_torso = load_bitmap("data/test/test_hero_front_torso.bmp")

		tile_map.chunk_shift = 4
		tile_map.chunk_dim = 256
		tile_map.chunk_mask = (1 << tile_map.chunk_shift) - 1

		tile_map.tile_chunk_count_x = 128
		tile_map.tile_chunk_count_y = 128
		tile_map.tile_chunk_count_z = 2

		tile_chunk_count :=
			tile_map.tile_chunk_count_x * tile_map.tile_chunk_count_y * tile_map.tile_chunk_count_z

		tile_map.tile_chunks = make([]Tile_Chunk, tile_chunk_count)

		tile_map.tile_side_in_meters = 1.4
		tile_map.tile_side_in_pixels = 60
		tile_map.meters_to_pixels =
			f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_meters

		lower_left_x := -tile_map.tile_side_in_pixels / 2
		lower_left_y := f32(p_buffer.height)
		tiles_per_width: u32 = 17
		tiles_per_height: u32 = 9
		screen_x := u32(0)
		screen_y := u32(0)
		door_left, door_right, door_top, door_bottom, door_up, door_down: bool

		rand.reset(u64(420))
		for screen_index := u32(0); screen_index < 100; screen_index += 1 {

			random := rand.int_max(3)

			created_z_door := false

			if random == 2 {
				created_z_door = true
				if abs_tile_z == 0 {
					door_up = true
				} else {
					door_down = true
				}
			} else if random == 1 {
				door_right = true
			} else {
				door_top = true
			}

			for tile_y: u32 = 0; tile_y < tiles_per_height; tile_y += 1 {
				for tile_x: u32 = 0; tile_x < tiles_per_width; tile_x += 1 {
					abs_tile_x := screen_x * tiles_per_width + tile_x
					abs_tile_y := screen_y * tiles_per_height + tile_y

					val := u32(1)

					if (tile_x == 0) {
						val = 2
						if (door_left && (tile_y == tiles_per_height / 2)) {
							val = 1
						}
					}

					if tile_x == tiles_per_width - 1 {
						val = 2
						if (door_right && (tile_y == tiles_per_height / 2)) {
							val = 1
						}
					}

					if (tile_y == 0) {
						val = 2
						if (door_bottom && (tile_x == tiles_per_width / 2)) {
							val = 1
						}
					}

					if (tile_y == (tiles_per_height - 1)) {
						val = 2
						if (door_top && tile_x == tiles_per_width / 2) {
							val = 1
						}
					}

					if tile_x == 10 && tile_y == 6 {
						if door_up {
							val = 3
						}
						if door_down {
							val = 4
						}
					}

					set_tile_value(world.tile_map, abs_tile_x, abs_tile_y, abs_tile_z, val)
				}

			}

			door_left = door_right
			door_bottom = door_top
			door_top = false
			door_right = false

			if created_z_door {
				door_down = !door_down
				door_up = !door_up
			} else {
				door_up = false
				door_down = false
			}

			if random == 2 {
				if abs_tile_z == 0 {
					abs_tile_z = 1
				} else {
					abs_tile_z = 0
				}
			} else if random == 1 {
				screen_x += 1
			} else {
				screen_y += 1
			}
		}
		p_game_memory.is_initialized = true
	}

	world := game_state.world
	tile_map := world.tile_map

	for i := 0; i < len(p_input.controllers); i += 1 {
		controller_input := p_input.controllers[i]
		if controller_input.is_analog {

		} else {
			d_player_x := f32(0.0)
			d_player_y := f32(0.0)

			if controller_input.move_right.ended_down {
				d_player_x = 1.0
			}
			if controller_input.move_left.ended_down {
				d_player_x = -1.0
			}
			if controller_input.move_down.ended_down {
				d_player_y = 1.0
			}
			if controller_input.move_up.ended_down {
				d_player_y = -1.0
			}

			player_speed: f32 = 2.0
			if controller_input.action_up.ended_down {
				player_speed = 10
			}
			d_player_x *= player_speed
			d_player_y *= player_speed

			new_player_p := game_state.player_p
			new_player_p.offset_x += p_input.dt_for_frame * d_player_x
			new_player_p.offset_y += p_input.dt_for_frame * d_player_y

			new_player_p = recanonicalize_position(tile_map, new_player_p)

			player_left := new_player_p
			player_left.offset_x -= 0.5 * player_width
			player_left = recanonicalize_position(tile_map, player_left)

			player_right := new_player_p
			player_right.offset_x += 0.5 * player_width
			player_right = recanonicalize_position(tile_map, player_right)

			if it_tile_map_empty(tile_map, new_player_p) &&
			   it_tile_map_empty(tile_map, player_left) &&
			   it_tile_map_empty(tile_map, player_right) {
				if !are_on_same_tile(&game_state.player_p, &new_player_p) {
					new_tile_val := get_tile_value(tile_map, new_player_p)

					if new_tile_val == 3 {
						new_player_p.abs_tile_z += 1
					} else if new_tile_val == 4 {
						new_player_p.abs_tile_z -= 1
					}
				}
				game_state.player_p = new_player_p
			}
		}
	}

	//draw_rectangle(p_buffer, 0, 0, f32(p_buffer.width), f32(p_buffer.height), 0.1, 0.1, 0.1)
	draw_bitmap(game_state.backdrop, p_buffer, 0, 0)

	screen_center_x: f32 = 0.5 * f32(p_buffer.width)
	screen_center_y: f32 = 0.5 * f32(p_buffer.height)

	h: f32 = f32(p_buffer.height)

	for rel_row: i32 = -10; rel_row < 100; rel_row += 1 {
		for rel_column: i32 = -20; rel_column < 200; rel_column += 1 {
			center_x :=
				screen_center_x -
				tile_map.meters_to_pixels * game_state.player_p.offset_x +
				f32(rel_column) * f32(tile_map.tile_side_in_pixels)
			center_y :=
				screen_center_y +
				tile_map.meters_to_pixels * game_state.player_p.offset_y -
				f32(rel_row) * f32(tile_map.tile_side_in_pixels)

			tile_min_x := center_x - 0.5 * f32(tile_map.tile_side_in_pixels)
			tile_min_y := center_y - 0.5 * f32(tile_map.tile_side_in_pixels)

			tile_max_x := tile_min_x + f32(tile_map.tile_side_in_pixels)
			tile_max_y := tile_min_y + f32(tile_map.tile_side_in_pixels)

			abs_x := u32(rel_column) + game_state.player_p.abs_tile_x
			abs_y := u32(rel_row) + game_state.player_p.abs_tile_y

			v := get_tile_value(tile_map, abs_x, abs_y, game_state.player_p.abs_tile_z)

			if v > 1 {
				gray: f32 = 0.5

				if v == 2 {
					gray = 1
				}

				if v > 2 {
					gray = .2
				}
				if abs_y == game_state.player_p.abs_tile_y &&
				   abs_x == game_state.player_p.abs_tile_x {
					gray = 0
				}

				draw_rectangle(
					p_buffer,
					tile_min_x,
					h - tile_max_y,
					tile_max_x,
					h - tile_min_y,
					gray,
					gray,
					gray,
				)
			}
		}
	}

	player_r := f32(1.0)
	player_g := f32(1.0)
	player_b := f32(0.0)

	player_left := screen_center_x - 0.5 * tile_map.meters_to_pixels * player_width
	player_top := screen_center_y - tile_map.meters_to_pixels * player_height

	draw_rectangle(
		p_buffer,
		player_left,
		player_top,
		player_left + tile_map.meters_to_pixels * player_width,
		player_top + tile_map.meters_to_pixels * player_height,
		player_r,
		player_g,
		player_b,
	)

	draw_bitmap(game_state.hero_cape, p_buffer, player_left, player_top)
}

load_bitmap :: proc(p_filename: string) -> ^img.Image {
	bmap: ^img.Image
	err: img.Error

	bmap, err = bmp.load_from_file(p_filename)
	if err != nil {
		fmt.println("Failed to load bmp")
		return nil
	}

	img.alpha_add_if_missing(bmap)

	return bmap
}

draw_bitmap :: proc(p_image: ^img.Image, p_buffer: ^Game_Backbuffer, p_dest_x, p_dest_y: f32) {
	if p_buffer.memory == nil {
		fmt.println("buffer memory is nil")
		return
	}

	image := p_image

	if image == nil {
		fmt.println("draw bitmap: image is nil")
		return
	}

	src_w := image.width
	src_h := image.height

	total_pixels := p_buffer.width * p_buffer.height
	dest_slice := mem.slice_ptr((^u32)(p_buffer.memory), int(total_pixels))

	for y in 0 ..< src_h {
		for x in 0 ..< src_w {
			target_x := p_dest_x + f32(x)
			target_y := p_dest_y + f32(y)

			if target_x < 0 ||
			   target_x >= f32(p_buffer.width) ||
			   target_y < 0 ||
			   target_y >= f32(p_buffer.height) {

				continue
			}

			src_index := (y * src_w + x) * image.channels

			r := image.pixels.buf[src_index + 0]
			g := image.pixels.buf[src_index + 1]
			b := image.pixels.buf[src_index + 2]
			a: u8 = 255

			if image.channels == 4 {
				a = image.pixels.buf[src_index + 3]
			}

			packed_color := (u32(a) << 24) | (u32(r) << 16) | (u32(g) << 8) | u32(b)

			dest_index := int(target_y) * int(p_buffer.width) + int(target_x)
			dest_slice[dest_index] = packed_color
		}
	}
}

/*draw_bitmap :: proc(p_buffer: ^Game_Backbuffer, p_bitmap: Loaded_Bitmp, px, py: f32, p_img : ^img.Image) {
	min_x := round_real32_to_int32(px)
	min_y := round_real32_to_int32(py)
	max_x := min_x + p_bitmap.width
	max_y := min_y + p_bitmap.height

	if min_x < 0 {
		min_x = 0
	}
	if min_y < 0 {
		min_y = 0
	}
	if max_x > p_buffer.width {
		max_x = p_buffer.width
	}
	if max_y > p_buffer.height {
		max_y = p_buffer.height
	}
	
	pixel := ([^]u32)(p_buffer.memory)
	bm_pixel := ([^]u32)(p_bitmap.pixels)


	for y in 0 ..< p_bitmap.height{
		buffer_y := min_y + y
		if buffer_y < 0 || buffer_y >= p_buffer.height {
			continue
		}
		for x in 0 ..< p_bitmap.width{
			buffer_x := min_x + x
			if buffer_x < 0 || buffer_x >= p_buffer.width{
				continue
			}

			index := y * p_bitmap.width + x
		
			src_pixel := bm_pixel[index]

			pixel[buffer_y * p_buffer.width + buffer_x] = src_pixel
		}
	}
	source_offset := cast(uintptr)(p_bitmap.pixels^ + u32(p_bitmap.width) * (u32(p_bitmap.height - 1)))
	dest_offset := cast(uintptr)(mem^ + u32(min_y) * u32(p_buffer.width) + u32(min_x))

	source_row: ^u32 = cast(^u32)(source_offset)
	dest_row: ^u32 = cast(^u32)(dest_offset)

	fmt.println(source_offset)
	fmt.println(dest_offset)

	for y := min_y; y < max_y; y += 1 {
		source: ^u32 = source_row
		dest: ^u32 = dest_row
		
		for x := min_x; x < max_x; x += 1 {
			dest^ += 1
			source^ += 1
			dest^ = source^
		}
		source_row = cast(^u32) (cast(uintptr)source_row - cast(uintptr)(p_bitmap.width))
		dest_row = cast(^u32) (cast(uintptr) + cast(uintptr)(p_buffer.width))
	}
}*/

draw_rectangle :: proc(
	p_buffer: ^Game_Backbuffer,
	p_real_min_x, p_real_min_y, p_real_max_x, p_real_max_y: f32,
	R, G, B: f32,
) {
	min_x := round_real32_to_int32(p_real_min_x)
	min_y := round_real32_to_int32(p_real_min_y)
	max_x := round_real32_to_int32(p_real_max_x)
	max_y := round_real32_to_int32(p_real_max_y)

	pixel := ([^]u32)(p_buffer.memory)

	color :=
		u32(round_real32_to_uint32(R * 255.0) << 16) |
		(round_real32_to_uint32(G * 255.0) << 8) |
		(round_real32_to_uint32(B * 255.0))

	if min_x < 0 {
		min_x = 0
	}
	if (min_y < 0) {
		min_y = 0
	}
	if max_x > p_buffer.width {
		max_x = p_buffer.width
	}
	if max_y > p_buffer.height {
		max_y = p_buffer.height
	}

	for y := min_y; y < max_y; y += 1 {
		for x := min_x; x < max_x; x += 1 {
			x_bit := x + min_x
			y_bit := y + min_y

			pixel[y * p_buffer.width + x] = color
		}
	}
}
