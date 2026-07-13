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

win32_process_xinput_digital_button :: proc(
	p_new_state, p_old_state: ^Game_Button_State,
	p_button_state: win.XINPUT_GAMEPAD_BUTTON, p_button_bit: win.XINPUT_GAMEPAD_BUTTON_BIT,
) {
	p_new_state.ended_down = p_button_bit in p_button_state
	p_new_state.half_transition_count = (p_old_state.ended_down != p_new_state.ended_down) ? 1 : 0
	
}

win32_process_xinput_stick_value :: proc(p_val : win.SHORT, p_dead_zone_threshold : win.SHORT) -> f32{
	result : f32

	if p_val < -p_dead_zone_threshold{
		result = (f32(p_val) + f32(p_dead_zone_threshold)) / (f32(32768.0) - f32(p_dead_zone_threshold))
		fmt.println(result)
	}
	if p_val > p_dead_zone_threshold{
		result = (f32(p_val) - f32(p_dead_zone_threshold)) / (f32(32767.0) - f32(p_dead_zone_threshold))
		fmt.println(result)
	}

	return result
}


win32_update_xinput :: proc(p_old_input, p_new_input: ^Game_Input) {
	max_controller_count := win.XUSER_MAX_COUNT

	if max_controller_count > (len(global_game_input.controllers) - 1) {
		max_controller_count = len(global_game_input.controllers) - 1
	}

	for i := 0; i < max_controller_count; i += 1 {
		state: win.XINPUT_STATE

		old_controller := &p_old_input.controllers[i + 1]
		new_controller := &p_new_input.controllers[i + 1]


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

			new_controller.stick_average_x = win32_process_xinput_stick_value(gamepad_state.sThumbLX, win.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
			new_controller.stick_average_y = win32_process_xinput_stick_value(gamepad_state.sThumbLY, win.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)

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
