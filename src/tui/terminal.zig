const std = @import("std");
const nc = @cImport({
    @cInclude("ncurses.h");
    @cInclude("menu.h");
    @cInclude("locale.h");
}); 

pub const Color = enum {
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White
};

pub const CharAttributes = enum {
    Normal,
    Standout,
    Underline,
    Reverse,
    Blink,
    Dim,
    Bold,
    Protect,
    Invis,
    AltCharSet,
    CharText

};


pub const ColorPair = struct {
    fg: Color,
    bg: Color
};

pub const CursesError = error {
    RoutineReturnedError
};

pub fn tryCurses(err: c_int) !void {
    if(err == -1) {
        return error.RoutineReturnedError;
    }
}
pub const Terminal = struct {
    pub fn init() !void {
        _ = nc.setlocale(nc.LC_ALL, "");
        _ = nc.initscr();
        try tryCurses(nc.refresh());
        try tryCurses(nc.raw());
        try tryCurses(nc.noecho());
        try tryCurses(nc.keypad(nc.stdscr, true));
        try tryCurses(nc.nodelay(nc.stdscr, true));
        try tryCurses(nc.cbreak());
    }

    pub fn quit() void {
        _ = nc.endwin();
        std.debug.print("Quitting\n", .{});
    } 

};

pub const MenuOption = struct {
    description: []const u8 
};

pub const MenuError = error {
    SelectionOutOfBounds
};

pub fn MenuEntry(comptime T: type) type {
    return struct {
        name: [:0]const u8,
        description: [:0]const u8 = "This is a long winded\ndescription", //TODO: Print struct info instead of this default
        data: T
    };
} 

pub fn MenuList(comptime T: type) type {
    return struct {
        const Self = @This();
        entries: std.ArrayList(MenuEntry(T)),     
        hovered_index: i32= 0,
        selected_index: ?i32= null, 

        pub fn init(alloc: std.mem.Allocator) Self {

            return Self {
                .entries = std.ArrayList(MenuEntry(T)).init(alloc) 
            };     
        }

        pub fn clearEntries(self: *Self) !void {
            self.hovered_index = 0;
            self.selected_index = null;

            self.entries.clearAndFree();
        }

        pub fn move(self: *Self, step: i32, max: u32) !void {
            const new_pos = self.hovered_index + step;
            if(new_pos >= 0 and new_pos < max)  {
                self.hovered_index = new_pos;
            } else {
                return error.SelectionOutOfBounds;
            }
        }
        
        pub fn addEntry(self: *Self, entry: MenuEntry(T)) !void {
            try self.entries.append(entry);
        }
        
        pub inline fn selectedEntry(self: *Self) ?MenuEntry(T) {
            if(self.selected_index) |i| {
                if(self.entries.items.len > 0) {
                    return self.entries.items[@intCast(usize, i)];
                }
            } 
            return null;
        }

        pub inline fn hoveredEntry(self: *Self) MenuEntry(T) {
            return self.entries.items[@intCast(usize, self.hovered_index)];
        }
        
        pub fn getMinCharWidth(self: *Self, comptime field_name: []const u8) usize {
            var max_len: usize = 0; 
            for(self.entries.items) |e| {
                const field = @field(e, field_name);

                const name_len = field.len;
                if(name_len > max_len){
                    max_len = name_len; 
                }
            }
            if(max_len == 0) {
                return 8; 
            }
            return max_len;
        }  
    };
}

pub fn Vec2(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        y: T,

        pub fn set1(n: T) Self {
            return .{.x = n, .y = n};
        }

        pub fn zero() Self {
            return .{.x = 0, .y = 0};
        }

        pub fn add(v1: Vec2(T), v2: Vec2(T)) Self {
            return Self {
                .x = v1.x + v2.x,
                .y = v1.y + v2.y
            };
        }
        pub fn sub(v1: Vec2(T), v2: Vec2(T)) Self {
            return Self {
                .x = v1.x - v2.x,
                .y = v1.y - v2.y
            };
        }

        pub fn addMut(self: *Self, other: Vec2(T)) void {
            self.x += other.x;
            self.y += other.y;
        }

    };
}
pub fn getScreenCenterX() i32 {
    return @divTrunc(nc.COLS, 2);
}

pub fn drawTitle(title: [:0]const u8) !void {
    try tryCurses(nc.move(0, getScreenCenterX() - 4));
    try tryCurses(nc.printw(title.ptr));
    try tryCurses(nc.move(0, 0));
    try tryCurses(nc.chgat(-1, nc.A_REVERSE, 0, null));
    try tryCurses(nc.refresh());
}
//TODO: Deal with magic numbers

pub fn ChoiceBox(comptime T: type) type {
    return struct {
        const Self = @This();
        title: [:0]const u8 = "ChoiceBox",
        description: [:0]const u8 = "Select an item!", 
        menu: MenuList(T),   
        window: ?LayeredWindow = null, 
        
        initialSize: Vec2(i32) = Vec2(i32).set1(4),

        size: Vec2(i32) = Vec2(i32).set1(0), 
        pos: Vec2(i32) = Vec2(i32).set1(0),

        descBoxOffset: Vec2(i32) = Vec2(i32).set1(0),
        descBoxSize: Vec2(i32) = Vec2(i32).set1(0),
        descBoxWindow: ?LayeredWindow = null,

        open: bool = true,
        visible: bool = false, 

        maxEntries: usize = 15,

        pagePos: usize = 1,

        pub fn autoScale(self: *Self) void {
            self.size.x =  @intCast(i32, self.menu.getMinCharWidth("name")) + 10;

            self.size.y = @intCast(i32, self.maxEntries + 3);
            self.descBoxSize.y = self.size.y; 
            self.descBoxSize.x = @intCast(i32, self.menu.getMinCharWidth("description")); 

            if(self.visible) {
                self.window.?.resize(self.size) catch unreachable;
                self.descBoxWindow.?.resize(self.descBoxSize) catch unreachable;
            }
        } 
        
        pub fn center(self: *Self) void {
            self.pos.x = @divTrunc((nc.COLS - @intCast(c_int, self.size.x)), 2);
            self.pos.y = @divTrunc((nc.LINES - @intCast(c_int, self.size.y)), 2);
            self.descBoxOffset.x = 5;             
        }
        
        pub fn left_align(self: *Self) void {
            self.pos.x = 0;
            self.pos.y = 1;
        }
        
        //TODO: Make menu a ptr maybe
        pub fn init(menu: MenuList(T), visible: bool) !Self {
            var box = Self {
                .menu = menu,
            };

            box.autoScale();
            box.left_align();

            if(visible) {
                try box.show();
            }

            return box;
        }

        pub fn show(self: *Self) !void {
            self.autoScale();

            if(!self.visible) {
                self.window = try LayeredWindow.new(self.size, self.pos, null);
                var descBoxPos: Vec2(i32) = Vec2(i32).add(self.pos,self.descBoxOffset);  
                descBoxPos.x += self.size.x + 3;
                self.descBoxWindow = try LayeredWindow.new(self.descBoxSize, descBoxPos, null);

                try tryCurses(nc.keypad(self.window.?.win, true));
                try tryCurses(nc.nodelay(self.window.?.win, true));
                try self.drawEntries();
                try self.drawBorder();
                try self.drawTitle();
                self.visible= true;
            }     
            try self.window.?.refresh();
        }

        pub fn drawBorder(self: *Self) !void {
            try self.window.?.drawBorder();
            try self.descBoxWindow.?.drawBorder();
        }
        
        
        pub fn drawTitle(self: *Self) !void {
            try tryCurses(nc.mvwprintw(self.window.?.outer, 0, 1, "🪟 %s", self.title.ptr));
            try tryCurses(nc.mvwprintw(self.descBoxWindow.?.outer, 0, 0, "❓ Info"));

            try self.window.?.refresh();
            try self.descBoxWindow.?.refresh();

        }

        pub fn drawEntries(self: *Self) !void {
            const entry_count = self.menu.entries.items.len;
            
            const start = self.pageStartPos(); 
            const max = std.math.min((self.pagePos * self.maxEntries), entry_count);  

            for(start..max) |i|{
                const entry = self.menu.entries.items[i];
                if(i == self.menu.hovered_index) {
                    try tryCurses(nc.wattron(self.window.?.win, nc.A_STANDOUT)); 
                    try tryCurses(nc.wclear(self.descBoxWindow.?.win));

                    try tryCurses(nc.mvwprintw(self.descBoxWindow.?.win, 0, 0, "%s", entry.description.ptr));

                    try tryCurses(nc.wrefresh(self.descBoxWindow.?.outer)); 

                    try self.descBoxWindow.?.refresh();
                    try self.window.?.refresh();

                } else {
                    try tryCurses(nc.wattroff(self.window.?.win, nc.A_STANDOUT)); 

                }
                try tryCurses(nc.mvwprintw(self.window.?.win, @intCast(c_int, i), 0, "%s", entry.name.ptr));
            }
            try self.window.?.refresh();
        }

        pub fn switchPage(self: *Self) !void {
            const entry_count = self.menu.entries.items.len;
            const current_max = ((self.pagePos) * self.maxEntries);

            if(current_max >= entry_count) {
                if(self.pagePos > 0) {
                    self.pagePos -= 1;
                    try self.window.?.clear();
                    try self.drawEntries();
                }    
            } else {
                self.pagePos += 1; 
                try self.window.?.clear();
                try self.drawEntries();
            } 
        }
        pub inline fn pageStartPos(self: *Self) usize {
            if(self.pagePos <= 0) 
                return 0;
            return (self.pagePos - 1) * self.maxEntries;
        }
        pub inline fn entryCount(self: *Self) usize {
            return self.menu.entries.items.len;
        }
        pub fn move(self: *Self, step: i32) !void {
            if(self.menu.entries.items.len > 0) {
                const new_pos = self.menu.hovered_index + step;
                const max = std.math.min(self.pagePos * self.maxEntries, self.entryCount());

                if(new_pos >= self.pageStartPos() and new_pos < max)  {
                    self.menu.hovered_index = new_pos;
                } else {
                    return error.SelectionOutOfBounds;
                }
            }
        }
        //TODO: Avoid duplication here
        pub fn run(self: *Self) !?T {
            while(self.open) {
                const char_down = nc.wgetch(self.window.?.win);
                if(char_down == 'q') {
                    self.open = false;
                    break;
                } 
                else if(char_down == 's') {
                    self.move(1) catch {};
                    try self.drawEntries();
                }

                else if(char_down == 'w') {
                    self.move(-1) catch {};
                    try self.drawEntries();
                }

                else if(char_down == 'c') {
                    self.open = false;
                    self.menu.selected_index = self.menu.hovered_index;
                    return self.menu.selectedEntry().?.data;
                }
                else if(char_down == 'p') {
                    try self.switchPage();
                    self.menu.hovered_index = @intCast(i32, self.pageStartPos());
                    try self.drawEntries();
                }
                std.time.sleep(std.time.ns_per_ms * 30);
            }
            return null;
        }

        pub const UserInput = union(enum) {
            data: T,
            quit: void,
            key: i32
        };  

        pub fn handleInput(self: *Self) !?UserInput  {
            const char_down = nc.wgetch(self.window.?.win);

            if(char_down == nc.ERR) {
                return null;
            }

            if(char_down == 'q') {
                self.open = false;
                return UserInput.quit;
            } 

            else if(char_down == 's') {
                self.move(1) catch {};
                try self.drawEntries();
            }

            else if(char_down == 'w') {
                self.move(-1) catch {};
                try self.drawEntries();
            }

            else if(char_down == 'c') {
                self.menu.selected_index = self.menu.hovered_index;
                if(self.menu.selectedEntry()) |entry| {
                    return UserInput {.data = entry.data};
                }
            }

            else if(char_down == 'p') {
                try self.switchPage();
                self.menu.hovered_index = @intCast(i32, self.pageStartPos());
                try self.drawEntries();
            }
            return UserInput {.key = char_down};
        }

        pub fn close(self: *Self) void {
            if(self.visible) {
                self.window.?.close();
                self.descBoxWindow.?.close();
                
                self.window = null;
                self.descBoxWindow = null;
                self.visible= false;
            }
        }
    };
}

pub const LayeredWindow = struct {
    win: *nc.WINDOW,
    outer: *nc.WINDOW,

    pub fn new(size: Vec2(i32), position: Vec2(i32), offset: ?Vec2(i32)) !LayeredWindow {
        const inner_offset = offset orelse Vec2(i32).set1(2);

        const outer_window = try new_window(Vec2(i32).add(size, inner_offset), position); 
        var border: i32 = 1; //TODO: Actual val
        const inner_window = try new_window(size, Vec2(i32).add(position, Vec2(i32).set1(border)));


        return LayeredWindow {
            .win = inner_window,
            .outer = outer_window
        };
    }

    pub fn refresh(self: *LayeredWindow) !void {
        try tryCurses(nc.wrefresh(self.win));
        try tryCurses(nc.wrefresh(self.outer));
    }

    pub fn drawBorder(self: *LayeredWindow) !void {
        try tryCurses(nc.box(self.outer, 0,0));
        try tryCurses(nc.wrefresh(self.outer));
    }
    pub fn clear(self: *LayeredWindow) !void {
        try tryCurses(nc.wclear(self.win));
        try self.refresh();
    }

    pub fn delBorder(self: *LayeredWindow) !void {
        try tryCurses(nc.wborder(self.outer, ' ', ' ', ' ',' ',' ',' ',' ',' ')); 
        try tryCurses(nc.wrefresh(self.outer));
    }

    pub fn close(self: *LayeredWindow) void {
        tryCurses(nc.wborder(self.outer, ' ', ' ', ' ',' ',' ',' ',' ',' ')) catch unreachable;
        self.clear() catch unreachable;
        _ = nc.wclear(self.outer);
        self.refresh() catch unreachable;
        _ = nc.wrefresh(self.outer);
        _ = nc.delwin(self.outer);
        _ = nc.delwin(self.win);
    }

    pub fn resize(self: *LayeredWindow, new_size: Vec2(i32)) !void {
        const inner_offset = Vec2(i32).set1(2);
        const inner_new_size = Vec2(i32).sub(new_size, inner_offset);
        try self.delBorder();
        

        try self.clear();
        try tryCurses(nc.wclear(self.outer));
        try tryCurses(nc.wresize(self.outer, @intCast(c_int, new_size.y), @intCast(c_int, new_size.x)));
        try tryCurses(nc.wresize(self.win, @intCast(c_int, inner_new_size.y), @intCast(c_int, inner_new_size.x)));

        try self.drawBorder();
        try self.refresh();
    } 
}; 

pub fn new_window(size: Vec2(i32), position: Vec2(i32)) !*nc.WINDOW {
    var wnd_ptr: *nc.WINDOW = nc.newwin(@intCast(c_int, size.y), @intCast(c_int, size.x), @intCast(c_int, position.y), @intCast(c_int, position.x)) orelse return error.RoutineReturnedError;
    return wnd_ptr;
}

pub const DebugWindow = struct {
    window: LayeredWindow,
    alloc: std.mem.Allocator,
    

    pub fn init(alloc: std.mem.Allocator) !DebugWindow {
        const position = Vec2(i32) {.x = 0, .y = nc.LINES - @divTrunc(nc.LINES, 2)};
        const size = Vec2(i32) {.x = nc.COLS - 2, .y = (nc.LINES - position.y) - 2};

        var window = try LayeredWindow.new(size, position, null);
        try window.drawBorder(); 

        return .{
            .window = window,
            .alloc = alloc
        };
    }

    pub fn print(self: *DebugWindow, comptime fmt: []const u8, args: anytype) void {
        //TODO: Handle scrolling
        const buffer = std.fmt.allocPrintZ(self.alloc, fmt, args) catch |e| {
            std.debug.print("error: {}\n", .{e});
            unreachable;
        };
        tryCurses(nc.wprintw(self.window.win, "[log] %s", buffer.ptr)) catch unreachable;
        self.window.refresh() catch unreachable;
    }
    
    pub fn clear(self: *DebugWindow) void {
        self.window.clear() catch unreachable;
    }
};
