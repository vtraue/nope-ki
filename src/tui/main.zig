const std = @import("std");
const win = @import("win32.zig"); 
const terminal = @import("terminal.zig"); 
const menu = @import("menu.zig");

const ESC = "\x1b";
const CSI = "\x1b[";

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    var term = try terminal.Terminal.init("Hello world"); 
    defer term.reset() catch unreachable;

    try term.clear();

    var app_menu = menu.Menu(i32).init(alloc.allocator(), &term, 1, onSelect);
    try app_menu.addEntry(.{.name = "Eintrag 1"});
    try app_menu.addEntry(.{.name = "Eintrag 2", .description = "fsdjhfsdfha;jdfa;klfdj"});
    try app_menu.addEntry(.{.name = "Eintrag 3", .description = null});
    try app_menu.addEntry(.{.name = "Eintrag 4", .description = "Blubbi"});
    try app_menu.addEntry(.{.name = "Eintrag 1"});
    try app_menu.addEntry(.{.name = "Eintrag 2", .description = "fsdjhfsdfha;jdfa;klfdj"});
    try app_menu.addEntry(.{.name = "Eintrag 3", .description = null});
    try app_menu.addEntry(.{.name = "Eintrag 4", .description = "Blubbi"});

    try app_menu.drawAll();
    try app_menu.run(alloc.allocator());
    
    //try term.rawPrint("Hey\n", .{});
    //try term.printExt(.{.x = 8, .y = 10}, .{.colorForeground = terminal.ColorCode.Green}, "Heya!", .{});
    //try term.printExt(.{.x = 5, .y = 9}, .{.colorForeground = terminal.ColorCode.Red}, "Blubbi!", .{});
    
    //try term.readInputRaw(alloc.allocator());
    
    //try stdout.print("\x1b[97m\x1b[100mThis text has a red foreground  öä using SGR.31.{u}\r\n", .{'💡'});
    //try stdout.print("\x1b[0mRestored state\r\n", .{});
    std.time.sleep(100000);
}
pub fn onSelect(context: i32, entry: *menu.MenuEntry) void {
    _ = entry;
    _ = context;

    std.debug.print("Blub", .{});
}
test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out dand see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
