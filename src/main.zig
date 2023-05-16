const std = @import("std");
const sio = @import("sio.zig");
const c = @import("sio_c.zig");
const util = @import("util.zig");
const http = @import("http.zig");
const game_client = @import("game_client.zig");
const game = @import("game.zig");
const json_parse = @import("json_parse.zig");
const tui = @import("tui/menu.zig");
const terminal = @import("tui/terminal.zig");
const win = @import("tui/win32.zig");
const menu = @import("tui/menu.zig");
var running = true;

pub const NewUser = struct {
    username: []const u8,
    password: []const u8,
    firstname: []const u8,
    lastname: []const u8,
};

pub const SocketAuth = struct { token: []const u8 };

pub fn mainTest() !void {
    const deck = game.makeDeck2();
    std.debug.print("Deck: {any} \n", .{deck});
}
const LoginContext = struct { curl: *http.CurlHandle, user: ?game_client.LoginUserData = null };

pub const App = struct {
    serverUrl: [:0]const u8,
    alloc: std.heap.ArenaAllocator,
    curl: http.CurlHandle,
    userInstance: game_client.VerifyTokenResponse,
    socket: sio.SocketIO,
    game: game.Game,
    terminal: terminal.Terminal,

    tournamentMenu: ?*menu.Menu(*App, game.Tournament) = null,

    pub fn notify(self: *App, comptime format: []const u8, args: anytype) void {
        if (self.tournamentMenu) |men| {
            men.notify(format, args) catch unreachable;
        }
    }
    pub fn init(comptime server: [:0]const u8, user: *const game_client.LoginUserData) !App {
        _ = user;

        var alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var term = try terminal.Terminal.init(alloc.allocator(), "Nope");
        try term.clear();
        try term.flush();

        var curl = try http.CurlHandle.init();
        var login_context: LoginContext = .{ .curl = &curl };

        var game_running = game.Game{ .game_state = null, .tournament_list = null };

        var login_menu = menu.Menu(*LoginContext, game_client.LoginUserData).init(alloc.allocator(), &term, &login_context, onLoginSelection);

        try login_menu.addEntry(.{ .name = "Zero", .data = game_client.LoginUserData{ .username = "Zero", .password = "123456" } });
        try login_menu.addEntry(.{ .name = "Ziggy", .data = game_client.LoginUserData{ .username = "Ziggy", .password = "123456" } });

        try login_menu.drawAll();

        var selecteed_user = blk: {
            while (true) {
                try login_menu.blockRun(alloc.allocator());
                if (login_context.user) |selected_user| {
                    break :blk selected_user;
                }
            }
        };

        const login_response: game_client.LoginUserResponse = login: {
            const url = server[0..] ++ "/api/auth/login";
            _ = url;
            //const request = game_client.LoginUserRequest{ .data = user.*, .url = "https://nope-server.azurewebsites.net/api/auth/login" };
            const request = game_client.LoginUserRequest{ .data = selecteed_user, .url = "https://nope-server.azurewebsites.net/api/auth/login" };
            const response = try game_client.userLogin(alloc.allocator(), &curl, request);
            break :login response;
        };

        const auth = SocketAuth{ .token = login_response.accessToken };
        _ = auth;
        const tok_request = game_client.VerifyTokenRequest{ .token = login_response.accessToken };
        const tok_response: game_client.VerifyTokenResponse = try game_client.tokenVerify(alloc.allocator(), &curl, tok_request);

        const auth_str = try std.cstr.addNullByte(alloc.allocator(), try std.json.stringifyAlloc(alloc.allocator(), tok_request, .{}));

        const client_info = sio.ClientParameters{
            .address = server,
            .namespace = "/",
            .auth = auth_str,
        };

        _ = win.Beep(750, 300);
        var socket_io = try sio.create_client(alloc.allocator(), client_info);

        var app = App{
            .serverUrl = server,
            .alloc = alloc,
            .curl = curl,
            .userInstance = tok_response,
            .socket = socket_io,
            .game = game_running,
            .terminal = term,
        };

        return app;
    }
};

pub fn main() !void {
    const user_data = game_client.LoginUserData{ .username = "Zero", .password = "123456" };
    var app = try App.init("https://nope-server.azurewebsites.net", &user_data);

    var app_menu = menu.Menu(*App, game.Tournament).init(app.alloc.allocator(), &app.terminal, &app, onSelect);
    app_menu.onHotkey = onHotkey;

    try app_menu.captureKey('l');
    try app_menu.captureKey('c');
    try app_menu.captureKey('b');

    app_menu.name = "🌟 Nope";

    try app_menu.drawAll();

    app.tournamentMenu = &app_menu;

    //
    //try game_client.userRegister(alloc.allocator(), &curl, .{
    //    .username = "Ziguana",
    //    .firstname = "Ziguana",
    //    .lastname = "Ziggy",
    //    .password = "123456"
    //});

    //const tournament_response = try game_client.createTournamentBlocking(alloc.allocator(), &socket_io, .{ .numBestOfMatches = 5 });
    //_ = tournament_response;

    //const tournament_id = "clhkhg4ik0000p907f5pedt3k";
    //_ = tournament_id;

    //try game_client.leaveTournament(alloc.allocator(), &socket_io);

    //try game_client.joinTournament(alloc.allocator(), &socket_io, tournament_id);

    //try game_client.startTournament(alloc.allocator(), &socket_io);

    std.debug.print("Entering loop\n", .{});

    _ = win.Beep(750, 300);

    while (app.tournamentMenu.?.isOpen) {
        //const ev = socket_io.events.block_pop_front();
        try app.tournamentMenu.?.peekRun(app.alloc.allocator());
        const event = app.socket.events.try_pop_front();

        if (event) |ev| {
            switch (ev.event) {
                .Custom => |rust_str| {
                    const event_str = rust_str.as_string_slice();
                    if (std.mem.eql(u8, event_str, "list:tournaments")) {
                        switch (ev.payload) {
                            .String => |str| {
                                app.game.tournament_list = try json_parse.readTournamentList(app.alloc.allocator(), str.as_string_slice());
                                if (app.game.tournament_list) |list| {
                                    app.tournamentMenu.?.clearEntries();
                                    for (list.items) |t| {
                                        const desc = try std.fmt.allocPrint(app.alloc.allocator(), "Status: {s}, From: {s} --- Id {s}", .{ t.status, t.createdAt, t.id });
                                        const name = try std.fmt.allocPrint(app.alloc.allocator(), "{}", .{t});
                                        try app.tournamentMenu.?.addEntry(.{ .name = name, .description = desc, .data = t });
                                    }
                                }
                            },
                            else => {},
                        }
                    } else if (std.mem.eql(u8, event_str, "match:invite")) {
                        try app_menu.notify("Its an invite!", .{});
                        try game_client.acceptMatchInvite(app.alloc.allocator(), app.userInstance.user.id, &app.socket, &ev);
                    } else if (std.mem.eql(u8, event_str, "game:state")) {
                        switch (ev.payload) {
                            .String => |str| {
                                try app_menu.notify("Game state notification:\n {s}", .{str.as_string_slice()});
                                app.game.game_state = try json_parse.readGameStateTokenStream(app.alloc.allocator(), str.as_string_slice(), &app);
                                try app_menu.notify("done!", .{});
                            },
                            else => {},
                        }
                    } else if (std.mem.eql(u8, event_str, "game:makeMove")) {
                        if (app.game.game_state) |state| {
                            try app_menu.notify("We got game:makeMove! TopCard: {?}", .{app.game.game_state.?.top_card});
                            try game.makeMove(app.alloc.allocator(), &state, &app.socket, &ev, &app);
                        }
                    }

                    try app_menu.notify("Got an event! {s}\n", .{event_str});
                },
                else => {},
            }
            switch (ev.payload) {
                .String => |str| {
                    try app_menu.notify("Payload: {s}\n", .{str.as_string_slice()});
                    //socket_io.client.disonnect();
                    //running = false;
                },
                else => {},
            }
        }
        std.time.sleep(41000000);
    }
    try app.terminal.reset();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

pub fn onSelect(context: *App, entry: *menu.MenuEntry(game.Tournament)) void {
    //const app_menu = @fieldParentPtr(menu.Menu(sio.SocketIO, game.Tournament), "onSelectData", context);
    if (context.game.is_in_tournament) {
        game_client.leaveTournament(context.alloc.allocator(), &context.socket) catch {
            context.tournamentMenu.?.notify("that didnt work", .{}) catch return;
        };
    }

    game_client.joinTournament(context.alloc.allocator(), &context.socket, entry.data.id) catch {
        context.tournamentMenu.?.notify("that didnt work", .{}) catch return;
    };
    context.game.is_in_tournament = true;

    context.tournamentMenu.?.notify("All done", .{}) catch return;
}

pub fn onLoginSelection(context: *LoginContext, entry: *menu.MenuEntry(game_client.LoginUserData)) void {
    context.user = entry.data;
}

pub fn onHotkey(context: *App, hotkey: u8) void {

    //Leave tournament
    if (hotkey == 'l') {
        game_client.leaveTournament(context.alloc.allocator(), &context.socket) catch {
            context.tournamentMenu.?.notify("that didnt work", .{}) catch return;
        };
        context.tournamentMenu.?.notify("Left tournament!", .{}) catch return;
    } else if (hotkey == 'c') {
        const response = game_client.createTournamentBlocking(context.alloc.allocator(), &context.socket, .{ .numBestOfMatches = 5 }) catch return;

        if (!response.success) {
            context.tournamentMenu.?.notify("that didnt work", .{}) catch return;
            return;
        }
        context.tournamentMenu.?.notify("Created new tournament", .{}) catch return;
    } else if (hotkey == 'b') {
        game_client.startTournament(context.alloc.allocator(), &context.socket) catch return;
        context.tournamentMenu.?.notify("Tried starting tournament", .{}) catch return;
    }
}
