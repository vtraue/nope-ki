const std = @import("std");
const builtin = @import("builtin");
const native_arch = builtin.cpu.arch;
const windows = std.os.windows;
pub const WINAPI: std.builtin.CallingConvention = if (native_arch == .x86) .Stdcall else .C;
pub const BOOL = c_int;
pub const BOOLEAN = BYTE;
pub const BYTE = u8;
pub const CHAR = u8;
pub const UCHAR = u8;
pub const FLOAT = f32;
pub const HANDLE = *anyopaque;
pub const DWORD = u32;
pub const HMODULE = *opaque {};
pub const TRUE = 1;
pub const FALSE = 0;
pub const FARPROC = *opaque {};

pub const STD_INPUT_HANDLE = std.os.windows.STD_INPUT_HANDLE;
pub const STD_OUTPUT_HANDLE = std.os.windows.STD_OUTPUT_HANDLE;

pub const ENABLLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
pub const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
pub const ENABLE_MOUSE_INPUT = 0x0010;
pub const ENABLE_WINDOW_INPUT = 0x0008;

pub const COORD = extern struct {
    x: i16,
    y: i16
};

pub const INPUT_RECORD = extern struct {
    pub const KEY_EVENT_RECORD = extern struct {
        pub const uChar = extern union {
            UnicodeChar: u16,
            AsciiChar: u8
        };
        bKeyDown: BOOL,
        wRepeatCount : u16,
        wVirtualKeyCode: u16,
        wVirtualScanCode: u16,
        _uChar: uChar,
        dwControlKeyState: DWORD
    };
    pub const MOUSE_EVENT_RECORD = extern struct {
        dwMousePosition: COORD,
        dwButtonState: DWORD,
        dwControlKeyState: DWORD,
        dwEventFlags: DWORD
    };
    pub const MENU_EVENT_RECORD = extern struct {
        dwCommandId: c_uint
    };
    pub const WINDOW_BUFFER_SIZE_RECORD = extern struct {
        dwSize: COORD
    };
    pub const FOCUS_EVENT_RECORD = extern struct {
        bSetFocus: bool
    };

    pub const Event = extern union {
        KeyEvent: KEY_EVENT_RECORD,
        MouseEvent: MOUSE_EVENT_RECORD,
        WindowBufferSizeEvent: WINDOW_BUFFER_SIZE_RECORD,
        MenuEvent: MENU_EVENT_RECORD,
        FocusEvent: FOCUS_EVENT_RECORD
    };

    EventType: u16,
    ev: Event,
};

pub extern "Kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(WINAPI) HANDLE;
pub extern "Kernel32" fn GetConsoleMode(hConsoleHandle: HANDLE, lpMode: ?*DWORD) callconv(WINAPI) BOOL;
pub extern "Kernel32" fn SetConsoleMode(hConsoleHandle: HANDLE, dwMode: DWORD) callconv(WINAPI) BOOL;
pub extern "Kernel32" fn SetConsoleOutputCP(wCodePageID: c_uint) BOOL;
pub extern "Kernel32" fn SetConsoleCP(wCodePageID: c_uint) BOOL;
pub extern "Kernel32" fn ReadConsoleW(hConsoleInput: HANDLE, lpBuffer: ?*anyopaque, nNumbersOfCharsToRead: DWORD, lpNumberOfCharsRead: ?*DWORD, pInputControl: ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "Kernel32" fn SetConsoleCursorPosition(hConsoleOutput: HANDLE, dwCursorPosition: COORD) callconv(WINAPI) BOOL;
pub extern "Kernel32" fn LoadLibaryA(lpLibFileName: [*:0]const u8) callconv(WINAPI) ?HMODULE;
pub extern "Kernel32" fn GetProcAddress(hModule: HMODULE, lpProcName: [*:0]const u8) callconv(WINAPI) ?FARPROC;
pub extern "Kernel32" fn PeekConsoleInputW(hConsoleInput: HANDLE, lpBuffer: [*]INPUT_RECORD, nLength: DWORD, lpNumberOfEventsRead: ?*DWORD) callconv(WINAPI) BOOL;
pub extern "Kernel32" fn ReadConsoleInputW(hConsoleInput: HANDLE, lpBuffer: [*]INPUT_RECORD, nLength: DWORD, lpNumberOfEventsRead: ?*DWORD) callconv(WINAPI) BOOL;
pub extern "Kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) callconv(WINAPI) DWORD;
pub extern "Kernel32" fn FlushConsoleInputBuffer(hConsoleInput: HANDLE) callconv(WINAPI) BOOL;
pub extern "Kernel32" fn Beep(dwFreq: DWORD, dwDuration: DWORD) callconv(WINAPI) BOOL;
pub extern "Kernel32" fn SetConsoleTextAttribute(hConsoleOutput: HANDLE, wAttributes: u16) callconv(WINAPI) BOOL;

pub const VTError = error {
    UnableToSetUTF8,
    UnableToRetrieveHandleValue,
    UnableToRetrieveMode, 
    UnableToSetMode,
    UnableToReadFromConsole
};


pub fn enableVTMode() !void {
    if(SetConsoleOutputCP(65001) == FALSE) {
        return error.UnableToSetUTF8; 
    }
    if(SetConsoleCP(65001) == FALSE) {
        return error.UnableToSetUTF8; 
    }

    //Enable VT Terminal Sequences for stdout
    const out_handle = GetStdHandle(STD_OUTPUT_HANDLE);
    if(out_handle == windows.INVALID_HANDLE_VALUE) {
        return error.UnableToRetrieveHandleValue;
    }     
    
    var current_mode: DWORD = 0; 
    if(GetConsoleMode(out_handle, &current_mode) == FALSE) {
        return error.UnableToRetrieveMode;
    }

    current_mode = ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if(SetConsoleMode(out_handle, current_mode) == FALSE) {
        return error.UnableToSetMode;
    }             

    //Enable VT Terminal Sequences for stdin
    const in_handle = GetStdHandle(STD_INPUT_HANDLE);
    var current_in_mode: DWORD = 0;

    if(GetConsoleMode(in_handle, &current_in_mode) == FALSE) {
        return error.UnableToRetrieveMode;
    }

    try setInteractiveMode(in_handle);
}

pub fn setInteractiveMode(handle: HANDLE) !void {
    const mode = ENABLLE_VIRTUAL_TERMINAL_INPUT | ENABLE_MOUSE_INPUT |  0x0008 | 0x0001;
    if(SetConsoleMode(handle, mode) == FALSE) {
        return error.UnableToSetMode;
    }             
}

pub fn setTextMode(handle: HANDLE) !void {
    const mode = ENABLLE_VIRTUAL_TERMINAL_INPUT | ENABLE_MOUSE_INPUT |  0x0008 | 0x0001 | 0x0002;
    if(SetConsoleMode(handle, mode) == FALSE) {
        return error.UnableToSetMode;
    }             

}

pub fn readConsole(alloc: std.mem.Allocator, handle: HANDLE, len: usize) ![]u8{
    var chars_read: u32 = 0;
    const wbuffer = try alloc.alloc(u16, len);
    const result = ReadConsoleW(handle, @constCast(wbuffer.ptr), @intCast(u32, len), &chars_read, null);
    const resultBuffer = try std.unicode.utf16leToUtf8Alloc(alloc, wbuffer);
    
    if(result == FALSE or chars_read == 0) {
        return error.UnableToReadFromConsole;
    }
    return resultBuffer; 
} 

pub fn peekConsoleInput(alloc: std.mem.Allocator, handle: HANDLE, record_buffer: []INPUT_RECORD) !?[]u8{
    var events_read: u32 = 0; 
    const result = PeekConsoleInputW(handle, record_buffer.ptr, @intCast(u32,record_buffer.len), &events_read);
    var wbuffer = [_]u16{0} ** 256; 
     
    if(result == FALSE) {
        return error.UnableToReadFromConsole;
    }

    var chars_read: u32 = 0;
    for(0..events_read) |i| {
        if(i >= wbuffer.len) {
            break;
        }
        if(record_buffer[i].EventType == 0x0001) {
            chars_read += 1;
            wbuffer[i] = record_buffer[i].ev.KeyEvent._uChar.UnicodeChar;
        }
    }

    if(events_read > 0) {
        _ = FlushConsoleInputBuffer(handle); 
    }
    if(chars_read > 0) {
        const resultBuffer = try std.unicode.utf16leToUtf8Alloc(alloc, &wbuffer);
        return resultBuffer;
    }

    return null; 
}
