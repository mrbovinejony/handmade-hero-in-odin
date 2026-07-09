package main

import "base:runtime"
import "core:fmt"
import win "core:sys/windows"

operation := win.WHITENESS
running : bool

bitmap_info: win.BITMAPINFO
bitmap_memory: rawptr
bitmap_handle: win.HBITMAP
bitmap_device_context: win.HDC

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

    if window != nil{
        running = true

        //odins version of "while" loop
        for running == true{
            message: win.MSG
            message_result:= win.GetMessageW(&message, nil, 0, 0)
            
            if message_result > 0{
                win.TranslateMessage(&message)
                win.DispatchMessageW(&message)
            }
        }
    }
}

win32_resize_dib_section :: proc(width, height: i32){
    if bitmap_handle != nil{
        win.DeleteObject(win.HGDIOBJ(bitmap_handle))
    }

    if bitmap_device_context == nil{
        bitmap_device_context = win.CreateCompatibleDC(nil)
    }

    bitmap_info = win.BITMAPINFO {
        bmiHeader ={
            biSize = size_of(win.BITMAPINFOHEADER),
            biWidth = width,
            biHeight = height,
            biPlanes = 1,
            biBitCount = 32,
            biCompression = win.BI_RGB,
        }
    }

    bitmap_handle := win.CreateDIBSection(bitmap_device_context, &bitmap_info, win.DIB_RGB_COLORS, &bitmap_memory, nil, 0)
}

win32_update_window :: proc(device_context: win.HDC, x, y, width, height: i32){
    win.StretchDIBits(device_context, x, y, width, height, x, y, width, height, 
                        bitmap_memory,
                        &bitmap_info,
                        win.DIB_RGB_COLORS, win.SRCCOPY)
}

//stdcall is needed when using win32 api, something to do with how parameters are pushed on the stack, matching the "c" way 
//but using this, the context pointer is not passed automatically which is why we need to get the context here
//comment out the context = line to get some error information

win32_main_window_callback :: proc "stdcall" (window: win.HWND, message: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) -> win.LRESULT{
    context = runtime.default_context()
    
    result: win.LRESULT
    
    switch message{
        case win.WM_SIZE:
            client_rect: win.RECT
            win.GetClientRect(window, &client_rect)
            width := client_rect.right - client_rect.left
            height := client_rect.bottom - client_rect.top
            win32_resize_dib_section(width, height)
            fmt.println("WM_SIZE")

        case win.WM_DESTROY:
            running = false
            fmt.println("WM_DESTROY")

        case win.WM_CLOSE:
            running = false
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

            win32_update_window(device_context, x, y, width, height)

            win.EndPaint(window, &paint)
            
        case:
            result = win.DefWindowProcW(window, message, wParam, lParam)
    }

    return result
}