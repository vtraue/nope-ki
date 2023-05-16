const std = @import("std");
const term = @import("terminal.zig");
const common = @import("common.zig");

pub const MenuOptions = struct {
    hover_format: term.Format = term.Format {.colorForeground = term.ColorCode.Black, .colorBackground = term.ColorCode.White},

    headline_offset: u32 = 2,
    descOffset: common.Position = .{.x = 0, .y = 5},

    keycode_up: u8 = 'w', 
    keycode_down: u8 = 's',
    keycode_right: u8 = 'd',
    keycode_left: u8 = 'a',

    keycode_select: u8 = 'x',
    keycode_quit: u8 = 'q',

    notifyPosition: common.Position = .{.x = 0, .y = 15},
};
//TODO: Make menu entry type generic. Remove the context thing
pub fn Menu(comptime on_select_data_type: type, comptime T: type) type {
    return struct {
        const Self = @This();
        const MenuSelectionCallback = *const fn(on_select_data_type, *MenuEntry(T)) void;
        const HotkeyCallback = *const fn(on_select_data_type, u8) void;
        
        name: []const u8 = "Unnamed Menu",
        position: common.Position = .{.x = 0, .y = 0}, 
        terminal: *term.Terminal,
        entries: std.ArrayList(MenuEntry(T)),
        hover: u32 = 0, 
        options: MenuOptions = .{},  
        isOpen: bool = true,
        onSelectData: on_select_data_type,
        onHotkey: ?HotkeyCallback = null,
        selectionCallback: MenuSelectionCallback, 
        capturedSymbols: std.ArrayList(u8),

        pub fn init(
            alloc: std.mem.Allocator, 
            terminal: *term.Terminal, 
            on_select_data: on_select_data_type, 
            callback: MenuSelectionCallback) Self {
            return .{
                .terminal = terminal,
                .entries = std.ArrayList(MenuEntry(T)).init(alloc),
                .onSelectData = on_select_data,
                .selectionCallback = callback,
                .capturedSymbols = std.ArrayList(u8).init(alloc)
            };
        }

        pub fn captureKey(self: *Self, symbol: u8) !void {
            if(std.mem.count(u8, self.capturedSymbols.items, &[_]u8{symbol}) == 0) {
                try self.capturedSymbols.append(symbol);
            }
        }

        pub fn handle_input(self: *Self, input: []u8) !void {
            if(input[0] == self.options.keycode_down) {
                if(self.hover < self.entries.items.len - 1) {
                    self.hover += 1; 
                    try self.drawAll();
                }
            }

            if(input[0] == self.options.keycode_up) {
                if(self.hover > 0) {
                    self.hover -= 1;
                    try self.drawAll();
                }
            }

            if(input[0] == self.options.keycode_quit) {
                self.isOpen = false;
            }

            if(input[0] == self.options.keycode_select) {
                try self.drawAll();
                try self.onItemSelect(); 
            }
            if(self.onHotkey) |callback| {
                for(self.capturedSymbols.items) |s| {
                    if(input[0] == s) {
                        callback(self.onSelectData, s);
                    }
                }
            }
        }

        pub fn onItemSelect(self: *Self) !void {
            if(self.entries.items.len > 0) {
                self.selectionCallback(self.onSelectData, &self.entries.items[self.hover]);
            }
        }
        pub fn clearEntries(self: *Self) void {
            self.entries.clearRetainingCapacity();
        }

        pub fn run(self: *Self, alloc: std.mem.Allocator) !void {
            while(self.isOpen) {
                const input_buffer = try self.terminal.readInputRaw(alloc);
                if(input_buffer) |input| {
                    try self.handle_input(input);

                }
                if(!self.isOpen) {
                    return;
                }
            }
        }

        pub fn blockRun(self: *Self, alloc: std.mem.Allocator) !void {
            const input_buffer = try self.terminal.readInputRaw(alloc);
            if(input_buffer) |input| {
                try self.handle_input(input);

            }
        }

        pub fn peekRun(self: *Self, alloc: std.mem.Allocator) !void {
            const input_buffer = try self.terminal.readInputRaw(alloc);
            if(input_buffer) |input| {
                try self.handle_input(input);

            }
            if(!self.isOpen) {
                return;
            }
        }
        pub fn drawAll(self: *Self) !void {
            try self.terminal.flush();
            try self.terminal.clear();
            try self.terminal.setCursorPos(self.position);     
            try self.terminal.printExt(null, .{.colorForeground = term.ColorCode.Green}, "{s}", .{self.name});
            try self.terminal.flush();
            try self.terminal.cursorMove(0, self.options.headline_offset);     
            for(0..self.entries.items.len) |i| {
                try self.drawEntry(i); 
            }
        }

        pub inline fn getEntryPosition(self: *Self, index: usize) common.Position {
            return .{
                .y = self.position.y + self.options.headline_offset + @intCast(u32, index),
                .x = self.position.x
            };
        }
        pub inline fn getDescPosition(self: *Self) common.Position {
            return .{
                .y = self.position.y + self.options.headline_offset + @intCast(u32, self.entries.items.len) + self.options.descOffset.y,
                .x = self.options.descOffset.x
            };
        } 
        
        pub fn notify(self: *Self, comptime format: []const u8, args: anytype) !void {
            try self.terminal.flush();
            try self.terminal.setCursorPos(self.options.notifyPosition);
            try self.terminal.deleteLines(1);
            try self.terminal.printExt(null, .{.colorForeground = term.ColorCode.Yellow}, "🤔 " ++ format, args);
            try self.terminal.logPrint(format, args);
            try self.terminal.flush();
            self.options.notifyPosition.y += 1;

            if(self.options.notifyPosition.y > 30) {
                self.options.notifyPosition.y = 15;
            }
        }

        pub fn drawEntry(self: *Self, index: usize) !void {
            //TODO: Do we have to delete here?
            try self.terminal.flush();

            const entry = self.entries.items[index]; 
            const pos = self.getEntryPosition(index);
            
            var format: ?term.Format = null; 

            //try self.terminal.setCursorPos(.{.x = self.position.x + self.options.descOffset.x, .y = self.position.y + self.options.descOffset.y});
            //try self.terminal.deleteLines(1);
            try self.terminal.flush();
            
            if(index == self.hover) {
                const desc_pos = self.getDescPosition();
                format = self.options.hover_format;

                if(entry.description) |desc| {
                    try self.terminal.setCursorPos(desc_pos);
                    try self.terminal.printExt(null, .{.underline = true, .bold = true}, "|(💡 {s})|", .{desc}); 
                    try self.terminal.flush();
                } else {
                    try self.terminal.setCursorPos(desc_pos);
                    try self.terminal.flush();
                }
            }


            try self.terminal.setCursorPos(pos);
            try self.terminal.printExt(null, format, "[🔴 {s}]", .{entry.name}); 

            try self.terminal.flush();
        }

        pub fn addEntry(self: *Self, entry: MenuEntry(T)) !void {
            try self.entries.append(entry); 
        }
    };
}

pub const Keybind = struct {
    
};

pub fn MenuEntry(comptime T: type) type {
    return struct {
        name: []const u8,
        description: ?[]const u8 = "This is a description",    
        data: T
    };
}
