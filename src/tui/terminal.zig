const std = @import("std");
const win = @import("win32.zig");
const common = @import("common.zig");
const ESC = "\x1b";
const CSI = "\x1b[";
const OSC = "\x1b]";
const ST = "\x1b\x5C";
pub const TerminalBufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);
pub const TerminalBufferedReader = std.io.BufferedReader(4096, std.fs.File.Reader);

pub const Cursor = struct {
    blinking: bool = false,
    visible: bool = true,
    position: common.Position = .{.x = 0, .y = 0}
};

pub const ColorCode = enum(u32) {
    Black = 0,
    Red = 1,
    Green = 2,
    Yellow = 3,
    Blue = 4,
    Magenta = 5,
    Cyan = 6,
    White = 7,
    Ex = 8,
    Default = 9
};
pub const ColorMode = enum(u32) {
    Foreground = 30,
    Background = 40,
    BrightForeground = 90,
    BrightBackground = 100
};

pub const Format = struct {
    bold: bool = false,
    underline: bool = false,
    swapColors: bool = false,
    colorForeground: ColorCode = ColorCode.Default,
    colorBackground: ColorCode = ColorCode.Default,
};

pub const Terminal = struct {
    stdout_file: std.fs.File,
    bw:  TerminalBufferedWriter,
    cursor: Cursor = .{},    
    title: ?[]const u8 = null,
    
    stdin_file: std.fs.File,
    br: TerminalBufferedReader,
    textMode: bool = false,
    inputBuffer: []win.INPUT_RECORD,
    
    stderr_file: std.fs.File,
    log_file: ?std.fs.File,

    pub fn init(alloc: std.mem.Allocator, title: ?[]const u8) !Terminal{
        try win.enableVTMode();

        const stdout_file = std.io.getStdOut();
        var bw = std.io.bufferedWriter(stdout_file.writer());

        var stdin_file = std.io.getStdIn();
        var br = std.io.bufferedReader(stdin_file.reader());

        var stderr_file = std.io.getStdOut();
        var log_file: ?std.fs.File = null;

        log_file = std.fs.cwd().createFile("log.txt", .{}) catch null;

        var term: Terminal = .{
            .inputBuffer = try alloc.alloc(win.INPUT_RECORD, 256),
            .stdout_file = stdout_file,
            .bw = bw,
            .stdin_file = stdin_file,
            .br = br,
            .stderr_file = stderr_file,
            .log_file = log_file
        };
        term.initErr();
        try term.switchTerminalBuffer();
        
        if(title) |str| {
            try term.setTitle(str);
        }
        try term.rawPrint("{s}?3h", .{CSI});
        try term.rawPrint("{s}?3l", .{CSI});
        try term.refreshCursorState();

        try term.flush();
        return term;
    }
    pub fn scrollDown(self: *Terminal, n: u32) !void {
        try self.rawPrint("{s}{}S", .{CSI, n});
    } 
    pub fn setTextMode(self: *Terminal) !void {
        self.textMode = true;
        win.setTextMode(self.stdin_file.handle);
    }

    pub fn disableTextMode(self: *Terminal) !void {
        self.textMode = false;
        win.setInteractiveMode(self.stdin_file.handle);
    }

    pub fn readInputRawTextBlocking(self: *Terminal, alloc: std.mem.Allocator) ![]u8{
        const buffer = try win.readConsole(alloc, self.stdin_file.handle, 1024);
        return buffer; 
    }
    pub fn readInputRaw(self: *Terminal, alloc: std.mem.Allocator) !?[]u8 {
        //const input_buffer = try self.br.reader().readUntilDelimiterOrEofAlloc(alloc, '\n', 100) orelse return;
        //try self.rawPrint("{s}\n", .{input_buffer}); 
        //const bytes_read = try self.stdin_file.read(&input_buffer);
        //const buffer = try win.readConsole(alloc, self.stdin_file.handle, 1024);
        const buffer = try win.peekConsoleInput(alloc, self.stdin_file.handle, self.inputBuffer);

        return buffer; 
    }

    pub fn printExt(
        self: *Terminal, 
        position: ?common.Position, 
        style: ?Format, 
        comptime format: []const u8, 
        args: anytype) !void {
        if(position) |pos| {
            try self.rawSetCursorPos(pos.y, pos.x);
        }

        if(style) |fmt| {
            try self.setFormat(fmt);
        }

        try self.rawPrint(format, args);
        //try self.refreshCursorState(); 

        try self.resetFormat();
        //try self.refreshCursorState();
    }

    pub fn printAt(
        self: *Terminal, 
        x: u32, 
        y: u32,
        comptime format: []const u8, 
        args: anytype) !void {
                    
        const old_position = self.cursor.position;
        try self.rawSetCursorPos(x, y);
        try self.rawPrint(format, args); 
        try self.rawSetCursorPos(old_position.x, old_position.y);
    }

    pub fn deleteLines(self: *Terminal, count: u32) !void {
        try self.rawPrint("{s}{}M", .{CSI, count});
    }
    pub fn resetFormat(self: *Terminal) !void {
        try self.rawPrint("{s}0m", .{CSI});
    } 

    pub fn setFormat(self: *Terminal, format: Format) !void {
        const bold: u32 = if(format.bold) 1 else 22;
        const underline: u32 = if(format.underline) 4 else 24;
        const swapColors: u32 = if(format.swapColors) 7 else 27;

        try self.rawPrint("{s}{};{};{};{};{}m", .{
            CSI,
            bold,
            underline,
            swapColors,
            @as(u32, (@enumToInt(format.colorForeground) + 30)),
            @as(u32, (@enumToInt(format.colorBackground) + 40)),
        });

    }

    pub fn refreshCursorState(self: *Terminal) !void {
        try self.rawSetCursorPos(self.cursor.position.x, self.cursor.position.y);

        //try self.rawPrint("{s}?12{s}", .{CSI, if(self.cursor.blinking) "h" else "l"});
        //try self.rawPrint("{s}25{s}", .{CSI, if(self.cursor.visible) "h" else "l"});
    }


    pub inline fn cursorMove(self: *Terminal, x: u32, y: u32) !void {
        return self.setCursorPos(.{.x = self.cursor.position.x + x, .y = self.cursor.position.y + y});
    }
    pub inline fn setCursorPos(self: *Terminal, pos: common.Position) !void {
        self.cursor.position = pos; 
        try self.rawSetCursorPos(pos.x, pos.y);
    }

    pub fn initErr(self: *Terminal) void {
        _ = win.SetConsoleCursorPosition(self.stderr_file.handle, .{.x = 1, .y = 10});
        //_ = win.SetConsoleTextAttribute(self.stderr_file.handle, 0x0004 | 0x0020);
        
    }
    pub inline fn rawSetCursorPos(self: *Terminal, x: u32, y: u32) !void {
        _ = win.SetConsoleCursorPosition(self.stdout_file.handle, .{.x = @intCast(i16, x), .y = @intCast(i16, y)});
    }

    pub fn setTitle(self: *Terminal, title: []const u8) !void {
        try self.rawPrint("{s}0;{s}{s}", .{OSC, title, ST});
    } 

    pub fn reset(self: *Terminal) !void {
        try self.resetTerminalBuffer(); 
        try self.softReset();
        try self.clear();

    }
    
    pub fn softReset(self: *Terminal) !void {
        try self.rawPrint("{s}!p", .{CSI});
    }

    pub fn switchTerminalBuffer(self: *Terminal) !void {
        try self.rawPrint("{s}?1049h",.{CSI});
    }  

    pub fn resetTerminalBuffer(self: *Terminal) !void {
        try self.rawPrint("{s}?1049l", .{CSI});
    } 

    pub fn clear(self: *Terminal) !void {
        try self.rawPrint("{s}2J", .{CSI});
    }

    pub inline fn rawPrint(self: *Terminal, comptime format: []const u8, args: anytype) !void {
        try self.bw.writer().print(format, args);
    }
    pub inline fn logPrint(self: *Terminal, comptime format: []const u8, args: anytype) !void {
        if(self.log_file) |log| {
            try log.writer().print(format, args);
        }
    }
    pub fn flush(self: *Terminal) !void {
        try self.bw.flush();
    }

};

