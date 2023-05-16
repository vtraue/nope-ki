const std = @import("std");

fn readNumberFromConsole() !u64 {
    const stdin = std.io.getStdIn().reader();
    _ = stdin;
    const stdout = std.io.getStdOut().writer();
    _ = stdout;

}