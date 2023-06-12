const std = @import("std");
const sio = @import("sio.zig");
const c = @import("sio_c.zig");
const util = @import("util.zig");
const http = @import("http.zig");
const game_client = @import("game_client.zig");
const game = @import("game.zig");
const json_parse = @import("json_parse.zig");
const tui = @import("tui/terminal.zig");

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

pub const Ui = struct {
    pub const UiState = enum { None, Login, TournamentSelect };

    tournamentSelection: tui.ChoiceBox(game.Tournament),
    state: UiState = UiState.Login,

    pub fn init(alloc: std.mem.Allocator) !Ui {
        const t_list = tui.MenuList(game.Tournament).init(alloc);
        var tournaments = try tui.ChoiceBox(game.Tournament).init(t_list, false);

        return Ui{ .tournamentSelection = tournaments };
    }
};
pub const App = struct {
    serverUrl: [:0]const u8,
    alloc: std.mem.Allocator,
    curl: http.CurlHandle,
    userInstance: game_client.VerifyTokenResponse,
    socket: sio.SocketIO,
    game: game.Game,
    debug: tui.DebugWindow,
    ui: Ui,
    running: bool = true,
    should_make_move: bool = false,
    real_opponent_hand_size: usize = 8,

    pub fn init(comptime server: [:0]const u8) !App {
        var alloc = std.heap.c_allocator;

        try tui.Terminal.init();
        try tui.drawTitle("Cardgame");
        var debug = try tui.DebugWindow.init(alloc);
        debug.print("Creating CURL handle...\n", .{});
        var curl = try http.CurlHandle.init();
        debug.print("...done\n", .{});
        var ui = try Ui.init(alloc);

        var login_menu_list = tui.MenuList(game_client.LoginUserData).init(alloc);
        try login_menu_list.addEntry(tui.MenuEntry(game_client.LoginUserData){ .name = "👤 Ziggy", .data = .{ .username = "Ziggy", .password = "123456" } });

        try login_menu_list.addEntry(tui.MenuEntry(game_client.LoginUserData){ .name = "👤 Zero", .data = .{ .username = "Zero", .password = "123456" } });

        try login_menu_list.addEntry(tui.MenuEntry(game_client.LoginUserData){ .name = "👤 Vivien", .data = .{ .username = "Vivien", .password = "123456" } });

        debug.print("Waiting for user input...\n", .{});
        var login_menu = try tui.ChoiceBox(game_client.LoginUserData).init(login_menu_list, true);

        const login_data = try login_menu.run() orelse {
            tui.Terminal.quit();
            login_menu.window.?.close();
            return error.UnableToInit;
        };

        login_menu.close();
        debug.print("...Done\n", .{});
        debug.clear();

        var game_running = game.Game{ .game_state = null, .tournament_list = null };

        const login_response: game_client.LoginUserResponse = login: {
            debug.print("Logging in...\n", .{});
            const url = server[0..] ++ "/api/auth/login";
            _ = url;

            const request = game_client.LoginUserRequest{ .data = login_data, .url = "https://nope-server.azurewebsites.net/api/auth/login" };
            const response = try game_client.userLogin(alloc, &curl, request);
            break :login response;
        };

        debug.print("Login done, User: {s} {s}\n", .{ login_response.user.firstname, login_response.user.lastname });
        debug.print("Verifying Token...\n", .{});

        const auth = SocketAuth{ .token = login_response.accessToken };
        _ = auth;
        const tok_request = game_client.VerifyTokenRequest{ .token = login_response.accessToken };
        const tok_response: game_client.VerifyTokenResponse = try game_client.tokenVerify(alloc, &curl, tok_request);

        const auth_str = try std.cstr.addNullByte(alloc, try std.json.stringifyAlloc(alloc, tok_request, .{}));
        const client_info = sio.ClientParameters{
            .address = server,
            .namespace = "/",
            .auth = auth_str,
        };
        debug.print("...done\n", .{});
        debug.print("Creating socket io client...", .{});

        var socket_io = try sio.create_client(alloc, client_info);
        debug.print("Done!\n", .{});

        debug.clear();

        var app = App{
            .serverUrl = server,
            .alloc = alloc,
            .curl = curl,
            .userInstance = tok_response,
            .socket = socket_io,
            .game = game_running,
            .debug = debug,
            .ui = ui,
        };

        return app;
    }

    pub inline fn getEvent(self: *App) ?sio.EventData {
        return self.socket.events.try_pop_front();
    }

    pub fn updateTournaments(self: *App, json_string: []u8) !void {
        self.debug.clear();
        //std.debug.print("{s}", .{json_string});
        const list = json_parse.readTournamentList(self.alloc, json_string) catch |e| {
            self.debug.print("Unable to read tournament list! {}\n", .{e});
            return e;
        };

        try self.ui.tournamentSelection.menu.clearEntries();

        self.debug.print("Updating tournament list...\n", .{});
        for (list) |t| {
            const desc = try std.fmt.allocPrintZ(self.alloc, "Status: {s}\nBy: {s}\nId {s}", .{ t.status, t.createdAt, t.id });

            const entry = tui.MenuEntry(game.Tournament){ .data = t, .name = try std.fmt.allocPrintZ(self.alloc, "{}", .{t}), .description = desc };
            try self.ui.tournamentSelection.menu.addEntry(entry);
        }

        self.debug.print("...done!\n", .{});

        try self.ui.tournamentSelection.show();

        self.ui.state = Ui.UiState.TournamentSelect;

        self.game.tournament_list = list;
    }

    pub inline fn onListTournaments(self: *App, payload: []u8) !void {
        self.updateTournaments(payload) catch |e| {
            self.debug.print("Unable to update tournament: {}\n", .{e});
        };
    }

    pub fn handleEvent(self: *App) !void {
        if (self.getEvent()) |ev| {
            if (self.should_make_move == true and self.game.game_state != null) {
                self.debug.print("Making move...\n", .{});
                try game.makeMove(self.alloc, &self.game.game_state.?, &self.socket, &ev);
                self.debug.print("Done\n", .{});
                self.should_make_move = false;
            }

            switch (ev.event) {
                .Custom => |rstr| {
                    const event_name = rstr.str();
                    self.debug.print("Got an event: {s}\n", .{event_name});

                    if (std.mem.eql(u8, event_name, "list:tournaments")) {
                        var actual_str = try ev.payload.String.to_str(self.alloc);
                        try self.updateTournaments(actual_str);
                        self.debug.print("Tournament count: {}\n", .{self.game.tournament_list.?.len});
                    }
                    if (std.mem.eql(u8, event_name, "match:invite")) {
                        self.debug.print("Got an invite\n", .{});
                        self.debug.print("Accepting invite...\n", .{});
                        try game_client.acceptMatchInvite(self.alloc, self.userInstance.user.id, &self.socket, &ev);
                        self.debug.print("Done!\n", .{});
                    } else if (std.mem.eql(u8, event_name, "game:state")) {
                        self.debug.clear();
                        std.debug.print("\nReading game state...\n", .{});
                        self.game.game_state = try json_parse.readGameStateTokenStream(self.alloc, ev.payload.String.as_string_slice(), self);
                        self.debug.print("...Done\n", .{});
                        self.debug.print("Top Card: {} hand size: {}\n", .{ self.game.game_state.?.top_card, self.game.game_state.?.hand_size });
                        //std.debug.print("New game state raw: {s}\n", .{ev.payload.String.as_string_slice()});
                        std.debug.print("GameState: \n\n{}", .{self.game.game_state.?});
                    } else if (std.mem.eql(u8, event_name, "game:makeMove")) {
                        if (self.game.game_state != null) {
                            std.debug.print("Making move...\n", .{});
                            try game.makeMove(self.alloc, &self.game.game_state.?, &self.socket, &ev);
                            std.debug.print("Done\n", .{});
                        } else {
                            self.should_make_move = true;
                        }
                    } else if (std.mem.eql(u8, event_name, "game:status")) {
                        self.debug.print("Game ended...\n", .{});
                        std.debug.print("Game ended: status: {s}\n", .{ev.payload.String.as_string_slice()});
                    }
                },
                else => unreachable,
            }
        }
    }
    pub fn joinTournament(self: *App, tournament: *const game.Tournament) !void {
        const response = try game_client.joinTournament(self.alloc, &self.socket, tournament.id);
        self.debug.print("Joined tournament: {s}\n", .{response});
        self.game.is_in_tournament = true;
    }

    pub fn leaveTournament(self: *App) !void {
        self.debug.print("Leaving tournament...\n", .{});
        const response = try game_client.leaveTournament(self.alloc, &self.socket);
        self.debug.print("...done: {s}\n", .{response});
        self.game.is_in_tournament = false;
    }

    pub inline fn createTournament(self: *App) !void {
        //TODO: User should be able to select num best of at some point
        const response = try game_client.createTournamentBlocking(self.alloc, &self.socket, .{});
        self.debug.print("Tournament creation response: {any}\n", .{response});
    }

    pub fn run(self: *App) !void {
        if (self.ui.state == Ui.UiState.None or self.ui.state == Ui.UiState.Login) {
            //Ignore all input (Maybe even fail, since we shouldnt be here...)
            return;
        } else if (self.ui.state == Ui.UiState.TournamentSelect) {
            if (try self.ui.tournamentSelection.handleInput()) |input| {
                switch (input) {
                    .quit => self.running = false,
                    .data => |t| {
                        self.joinTournament(&t) catch |e| {
                            self.debug.print("ERROR: Unable to join tournament: {}\n", .{e});
                            return e;
                        };
                    },
                    .key => |key| {
                        if (key == 'n') {
                            self.debug.print("Creating tournament...\n", .{});
                            try self.createTournament();
                            self.debug.print("...Done\n", .{});
                        } else if (key == 'b') {
                            self.debug.print("Starting tournament...\n", .{});
                            const response = try game_client.startTournament(self.alloc, &self.socket);
                            self.debug.print("Response: {s}", .{response});
                        } else if (key == 'l') {
                            try self.leaveTournament();
                        }
                    },
                }
            }
        }
    }
};

pub const AppError = error{UnexpectedPayloadType};

pub fn main() !void {
    var app = try App.init("https://nope-server.azurewebsites.net");

    app.debug.print("Waiting for the server to catch up...\n", .{});
    std.time.sleep(100000000);
    app.debug.print("...Done\n", .{});

    app.debug.print("Entering main loop!\n", .{});

    while (app.running) {
        app.run() catch |e| {
            std.debug.print("Error (run): {}\n", .{e});
        };
        app.handleEvent() catch |e| {
            std.debug.print("Error: (handleEvent){}\n", .{e});
            continue;
        };

        std.time.sleep(30 * std.time.ns_per_ms);
    }
}
