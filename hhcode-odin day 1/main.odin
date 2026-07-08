package main

import "core:fmt"
import "core:sys/windows"

main :: proc(){

    hInstance := windows.GetModuleHandleA(nil)

    //get cmd line parameters if used
    cmd_line := windows.GetCommandLineW()

    windows.MessageBoxW(nil, "ODINggfgf", "wingui", windows.MB_OK)
}