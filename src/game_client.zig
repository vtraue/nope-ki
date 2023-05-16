const std = @import("std");
const sio = @import("sio.zig");
const http = @import("http.zig");
const util = @import("util.zig");
const main = @import("main.zig");

pub fn ServerSocketResponse(T: type) type {
    return struct {
        success: bool,
        data: T,
        @"error": ?TournamentJsonError,
    };
}

pub const TournamentError = error{NoTournamentAvailable};

pub const TournamentJsonError = struct { message: []const u8 };

pub const TournamentCreationResponseData = struct {
    bestOf: u32, //Match count
    currentSize: u32, //Current player count
    tournamentId: []const u8, //who knows
};

pub const TournamentCreationResponse = struct {
    data: TournamentCreationResponseData,
    @"error": ?TournamentJsonError,
    success: bool,
};

pub const TournamentCreationRequest = struct { numBestOfMatches: u32 };

pub const Tournament = struct {};

pub const LoginUserData = struct { username: []const u8, password: []const u8 };

pub const LoginUserRequest = struct { url: [:0]const u8, data: LoginUserData };

pub const UserData = struct { username: []const u8, firstname: []const u8, lastname: []const u8, password: []const u8 };

pub const User = struct { id: []const u8, username: []const u8, firstname: []const u8, lastname: []const u8 };

pub const LoginUserResponse = struct { accessToken: []const u8, user: User };

pub const GameError = error{
    RegistrationRefused,
    LoginRefused,
    TokenRefused,
    AlreadyInTournament
};

pub const UserSession = struct { id: []const u8, username: []const u8 };

pub const VerifyTokenResponse = struct { user: UserSession };

pub const VerifyTokenRequest = struct {
    token: []const u8,
};

pub fn tokenVerify(alloc: std.mem.Allocator, curl: *http.CurlHandle, request: VerifyTokenRequest) !VerifyTokenResponse {
    const user_str = try std.json.stringifyAlloc(alloc, request, .{});
    var http_request = http.Request{
        .url = "https://nope-server.azurewebsites.net/api/verify-token",
        //.url = "localhost:4040/api/verify-token",
        .request_type = http.RequestType{ .Post = user_str},
        .verbose_log = false,
    };
    const http_response = try curl.send_request(alloc, &http_request);

    if (http_response.status_code != 200) {
        return error.TokenRefused;
    }
    var stream = std.json.TokenStream.init(http_response.data.items);
    const response = try std.json.parse(VerifyTokenResponse, &stream, .{ .allocator = alloc });

    return response;
}

pub fn userRegister(alloc: std.mem.Allocator, curl: *http.CurlHandle, user_data: UserData) !void {
    const user_str = try std.json.stringifyAlloc(alloc, user_data, .{});

    var request = http.Request{
        .url = "https://nope-server.azurewebsites.net/api/auth/register",
        //.url = "https://localhost:4040",
        .request_type = http.RequestType{ .Post = user_str},
        .verbose_log = false,
    };
    const response = try curl.send_request(alloc, &request);

    if (response.status_code != 201) {
        return error.RequestRejectedByServer;
    }
}

//test "registerSimple" {
//    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
//    var curl = try http.CurlHandle.init();
//    const user = UserData {.username = "Ziggy", .password = "123456", .firstname = "Ziggy", .lastname = "Stardust"};

//    try userRegister(alloc.allocator(), &curl, user);
//}
test "loginAndVerifyUser" {
    std.debug.print("heya", .{});
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    var curl = try http.CurlHandle.init();
    const user_data = LoginUserData{ .username = "Ziggy", .password = "123456" };

    const login_response: LoginUserResponse = login: {
        const request = LoginUserRequest{ .data = user_data, .url = "https://nope-server.azurewebsites.net/api/auth/login" };
        const response = try userLogin(alloc.allocator(), &curl, request);
        break :login response;
    };

    const tok_response: VerifyTokenResponse = try tokenVerify(alloc.allocator(), &curl, VerifyTokenRequest{ .token = login_response.accessToken });
    std.debug.print("user response name: {s}\n", .{tok_response.user.username});
}

pub fn userLogin(alloc: std.mem.Allocator, curl: *http.CurlHandle, request: LoginUserRequest) !LoginUserResponse {
    const login_str = try std.json.stringifyAlloc(alloc, request.data, .{});
    var http_request = http.Request{ .url = request.url, .request_type = http.RequestType{ .Post = login_str }, .verbose_log = false, };
    const http_response = try curl.send_request(alloc, &http_request);
    //TODO: Handle errors correctly
    std.debug.print("http response: {}\n", .{http_response});
    var stream = std.json.TokenStream.init(http_response.data.items);
    const repsonse = try std.json.parse(LoginUserResponse, &stream, .{ .allocator = alloc });

    return repsonse;
}


pub fn createTournamentBlocking(
    alloc: std.mem.Allocator, 
    socket: *sio.SocketIO, 
    tournament_info: TournamentCreationRequest) !TournamentCreationResponse {
    _ = tournament_info;
    //const req_str = try std.json.stringifyAlloc(alloc, tournament_info, .{});
    const req_str = "5"; 
    const context = @fieldParentPtr(main.App, "socket", socket);

    socket.client.emit(.{
        .payload = sio.Payload {.String = util.RustString.from_slice(req_str)},
        .event = sio.EventType{.Custom = util.RustString.from_slice("tournament:create")}

    });
    const ev = socket.acks.block_pop_front();

    context.notify("All done", .{});
    context.notify("createTournamentBlocking: Got response!\n", .{});

    switch (ev) {
        .String => |str| {
            const response_string = str.as_string_slice();
            const json_string = response_string[1 .. response_string.len - 1];
            context.notify("got: {s}\n", .{json_string});
            var stream = std.json.TokenStream.init(json_string);
            const response = try std.json.parse(TournamentCreationResponse, &stream, .{ .allocator = alloc });
            return response;
        },
        .Binary => |_| unreachable,
    }
}

fn createTournament(alloc: std.mem.Allocator, client: *sio.SocketIO, num_best_of: i32) !void {
    _ = num_best_of;
    _ = client;
    _ = alloc;
    const response: ServerSocketResponse(TournamentCreationResponseData) = .{
        .success = true,
    };

    _ = response;
}

pub fn joinTournament(alloc: std.mem.Allocator, socket: *sio.SocketIO, tournament_id: []const u8) !void {
    _ = alloc;
    const context = @fieldParentPtr(main.App, "socket", socket);

    socket.client.emit(.{
        .payload = sio.Payload {.String = util.RustString.from_slice(tournament_id)},
        .event = sio.EventType{.Custom = util.RustString.from_slice("tournament:join")}
    });  
    const ev = socket.acks.block_pop_front();
    context.notify("joinTournament: Got response!\n", .{});
    switch(ev) {
        .String => |str| {
            const response_str = str.as_string_slice();
            context.notify("got: {s}\n", .{response_str});
        },
        .Binary => |_| unreachable,
    }

}

pub fn leaveTournament(alloc: std.mem.Allocator, socket: *sio.SocketIO) !void {
    _ = alloc;
    const context = @fieldParentPtr(main.App, "socket", socket);
    socket.client.emit(.{
        .payload = null,
        .event = sio.EventType {.Custom = util.RustString.from_slice("tournament:leave")}
    });

    const ev = socket.acks.block_pop_front();
    context.notify("leaveTournament: Got response!\n", .{});   
    switch(ev) {
        .String => |str| {
            const response_str = str.as_string_slice();
            context.notify("got: {s}\n", .{response_str});
        },
        .Binary => |_| unreachable,
    }     
}

pub fn startTournament(alloc: std.mem.Allocator, socket: *sio.SocketIO) !void {
    _ = alloc;
        socket.client.emit(.{
        .payload = null,
        .event = sio.EventType {.Custom = util.RustString.from_slice("tournament:start")}
    });
    const context = @fieldParentPtr(main.App, "socket", socket);
    const ev = socket.acks.block_pop_front();
    context.notify("startTournament: Got response!\n", .{});   
    switch(ev) {
        .String => |str| {
            const response_str = str.as_string_slice();
            context.notify("got: {s}\n", .{response_str});
        },
        .Binary => |_| unreachable,
    }
}

pub fn acceptMatchInvite(alloc: std.mem.Allocator, player_id: []const u8, socket: *sio.SocketIO, event: *const sio.EventData) !void {
    const context = @fieldParentPtr(main.App, "socket", socket);
    context.notify("accept match invite", .{});    
    const payload_string = try std.json.stringifyAlloc(alloc, .{.accepted = true, .id =  player_id}, .{});

    const payload = sio.Payload {
    .String = util.RustString.from_slice(payload_string)
   };  

    socket.client.ack_message(event.id.? , payload);
    context.notify("accept match invite DONE", .{});    
}
