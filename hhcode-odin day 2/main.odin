package main

import "base:runtime"
import "core:fmt"
import win "core:sys/windows"

operation := win.WHITENESS

main :: proc(){

    instance := win.HINSTANCE(win.GetModuleHandleW(nil))

    //get cmd line parameters if used
    cmd_line := win.GetCommandLineW()

    window_class := win.WNDCLASSW {
        style = win.CS_OWNDC | win.CS_HREDRAW | win.CS_VREDRAW,
        lpfnWndProc = win32_main_window_callback,
        hInstance = instance,
        lpszClassName = "HandmadeHeroWindowClass",
    }

    if win.RegisterClassW(&window_class) == 0{
        fmt.println("failed to register window class")
        return
    }

    window := win.CreateWindowExW(
        0, window_class.lpszClassName, "handmade hero",
        win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
        win.CW_USEDEFAULT, win.CW_USEDEFAULT,
        win.CW_USEDEFAULT, win.CW_USEDEFAULT,
        nil, nil, instance, nil
    )

    if window == nil{
        fmt.println("failed to create window")
        return
    }

        for {
            message: win.MSG
            message_result:= win.GetMessageW(&message, nil, 0, 0)
            
            if message_result > 0{
                win.TranslateMessage(&message)
                win.DispatchMessageW(&message)
            }else{
                break
            }
        }
    
}

//stdcall is needed when using win32 api, something to do with how parameters are pushed on the stack, matching the "c" way 
//but using this, the context pointer is not passed automatically which is why we need to get the context here
//comment out the context = line to get some error information

win32_main_window_callback :: proc "stdcall" (window: win.HWND, message: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) -> win.LRESULT{
    context = runtime.default_context()
    
    result: win.LRESULT
    
    switch message{
        case win.WM_SIZE:
            fmt.println("WM_SIZE")

        case win.WM_DESTROY:
            fmt.println("WM_DESTROY")

        case win.WM_CLOSE:
            fmt.println("WM_CLOSE")

        case win.WM_ACTIVATEAPP:
            fmt.println("WM_ACTIVEAPP")
        
        case win.WM_PAINT:
            paint: win.PAINTSTRUCT
            device_context := win.BeginPaint(window, &paint)

            x := paint.rcPaint.left
            y := paint.rcPaint.top;
            width := paint.rcPaint.right - paint.rcPaint.left
            height := paint.rcPaint.bottom - paint.rcPaint.top

            if operation == win.WHITENESS{
                operation = win.BLACKNESS
            }else{
                operation = win.WHITENESS
            }
            win.PatBlt(device_context, x, y, width, height, operation)

            win.EndPaint(window, &paint)
            
        case:
            result = win.DefWindowProcW(window, message, wParam, lParam)
    }

    return result
}