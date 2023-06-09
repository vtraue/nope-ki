const game = @import("game.zig");
const sio = @import("sio.zig");
const std = @import("std");
const util = @import("util.zig");
const main = @import("main.zig");
// maybe not the best way, lets try something different
pub fn readGameStateDynamic(alloc: std.mem.Allocator, event: *sio.EventData) !game.GameState {
    var parser = std.json.Parser.init(alloc, false);
    var tree = try parser.parse(event.payload);
    defer tree.deinit();
    var match_id = tree.root.Object.get("matchId").?.String;
    _ = match_id;
    var game_id = tree.root.Object.get("gameId").?.String;
    _ = game_id;

    var top_card_list = tree.root.Object.get("topCard").?;
    var last_top_card_list = tree.root.Object.get("lastTopCard").?;
    _ = last_top_card_list;
    var draw_pile_size = @intCast(usize, (tree.root.Object.get("drawPileSize").?.Integer));
    _ = draw_pile_size;
    var players_list = tree.root.Object.get("players").?;
    _ = players_list;
    var own_hand_list = tree.root.Object.get("hand").?;
    _ = own_hand_list;
    var hand_size = @intCast(usize, (tree.root.Object.get("handSize").?.Integer));
    _ = hand_size;
    var current_player_list = tree.root.Object.get("currentPlayer").?;
    _ = current_player_list;

    var top_card: game.Card = .{
        .cardType = top_card_list.Array.items[0].object.get("type").?,
    };
    _ = top_card;
    //var last_top_card: game.Card;
    var players: std.ArrayList(game.Player) = std.ArrayList(game.Player).init(alloc);
    _ = players;
    //var own_hand: game.Hand;

    //var game_state: game.GameState;

}
//ICard from Server
pub const CardServerData = struct {
    color: ?[]const u8,
    type: []const u8,
    value: ?u32,

    //Wtf is going on with these?
    select: ?u32 = null,
    selectValue: ?u32 = null,
    selectedColor: ?[]const u8 = null,
};

// Move with CardServerData, not own game.Card
pub const MoveServerData = struct {
    type: []const u8,
    card1: ?CardServerData,
    card2: ?CardServerData,
    card3: ?CardServerData,
    reason: []const u8 = "no reason",
};

// GameState like we get it as json
pub const GameStateServerData = struct {
    currentPlayer: game.PlayerIdentity,
    currentPlayerIdx: u32,
    drawPileSize: u32,
    gameId: []const u8,
    hand: []CardServerData,
    handSize: u32,
    lastMove: ?MoveServerData,
    lastTopCard: ?CardServerData,
    matchId: []const u8,
    players: []game.Player,
    prevPlayer: ?game.PlayerIdentity,
    prevPlayerIdx: ?u64,
    prevTurnCards: []CardServerData,
    topCard: CardServerData,
};

// FIXME: This leaks an insane amount of memory. fix
// something different... to read and convert game:state json payload to own game.GameState struct
pub fn readGameStateTokenStream(alloc: std.mem.Allocator, payload_string: []const u8, app: *main.App) !game.GameState {
    std.debug.print("raw json in readGameStateTokenStream: {s}", .{payload_string});
    const parsedGameState = try std.json.parseFromSlice(GameStateServerData, alloc, payload_string, .{ .ignore_unknown_fields = true });

    const last_move = blk: {
        if (parsedGameState.lastMove) |move| {
            var move_cards = [_]?game.Card{null} ** 3;
            const last_move_cards = [_]*const ?CardServerData{ &move.card1, &move.card2, &move.card3 };

            for (0.., last_move_cards) |i, c| {
                move_cards[i] = if (c.*) |card| try game.Card.fromServerInfo(card) else null;
            }

            const last_move_type = std.meta.stringToEnum(game.MoveType, move.type) orelse return error.InvalidCard;
            const last_move = game.Move{
                .move_type = last_move_type,
                .cards = move_cards,
                .reason = move.reason,
            };

            break :blk last_move;
        }
        break :blk null;
    };

    // things to make sure, that we have the hand size of our opponent
    // if last move was "take", the players array only has us as player, not the prev player
    var opponent_hand_size: usize = 8;
    if (last_move) |lm| {
        if (lm.move_type == game.MoveType.take) {
            opponent_hand_size = app.real_opponent_hand_size;
        }
    }

    if (parsedGameState.prevPlayerIdx) |prev_player_index| {
        opponent_hand_size = parsedGameState.players[prev_player_index].handSize;
        app.real_opponent_hand_size = opponent_hand_size;
    }

    // convert Cards and hand from Server to own game.Card struct
    const top_card = try game.Card.fromServerInfo(parsedGameState.topCard);

    const last_top_card = if (parsedGameState.lastTopCard) |lastTopCard|
        try game.Card.fromServerInfo(lastTopCard)
    else
        null;

    var hand_cards = try std.ArrayList(game.Card).initCapacity(alloc, parsedGameState.hand.len);

    for (parsedGameState.hand) |f| {
        var card = try game.Card.fromServerInfo(f);
        try game.Card.setDefaultPrio(&card, opponent_hand_size, last_top_card);
        try hand_cards.append(card);
    }

    const hand = game.Hand{
        .cards = hand_cards,
    };

    var prev_turn_cards = try std.ArrayList(game.Card).initCapacity(alloc, parsedGameState.hand.len);

    for (parsedGameState.prevTurnCards) |f| {
        try prev_turn_cards.append(try game.Card.fromServerInfo(f));
    }

    //
    // finally game_state as game.GameState with all converted fields
    const game_state = game.GameState{
        .match_id = parsedGameState.matchId,
        .game_id = parsedGameState.gameId,
        .top_card = top_card,
        .last_top_card = last_top_card,
        .draw_pile_size = parsedGameState.drawPileSize,
        .players = parsedGameState.players,
        .own_hand = hand,
        .hand_size = parsedGameState.handSize,
        .current_player = parsedGameState.currentPlayer,
        .current_player_index = parsedGameState.currentPlayerIdx,
        .prev_player = parsedGameState.prevPlayer,
        .prev_player_index = parsedGameState.prevPlayerIdx,
        .prev_turn_cards = prev_turn_cards,
        .last_move = last_move,
        .opponent_hand_size = opponent_hand_size,
    };

    return game_state;
}

pub fn readStringColors(color_string: []const u8) ![2]?game.Color {
    var it = std.mem.tokenize(u8, color_string, "-");
    var i: u32 = 0;
    var color_array = [_]?game.Color{ null, null };

    while (it.next()) |c| {
        var real_color: ?game.Color = null;
        if (std.mem.eql(u8, c, "red")) {
            real_color = game.Color.red;
        } else if (std.mem.eql(u8, c, "green")) {
            real_color = game.Color.green;
        } else if (std.mem.eql(u8, c, "blue")) {
            real_color = game.Color.blue;
        } else if (std.mem.eql(u8, c, "yellow")) {
            real_color = game.Color.yellow;
        } else if (std.mem.eql(u8, c, "multi")) {
            real_color = game.Color.multi;
        }
        color_array[i] = real_color;
        i += 1;
    }
    return color_array;
}

pub fn colorToString(color: ?game.Color) ![]const u8 {
    if (color) |c| {
        if (c == game.Color.noColor) {
            return "";
        }
        const val = @enumToInt(c);
        const names = std.meta.fieldNames(game.Color);

        return names[val];
    }
    return "";
}

pub fn colorsToCombinedString(alloc: std.mem.Allocator, colors: [2]?game.Color) !?[]const u8 {
    if (colors[0] == null and colors[1] == null) {
        return null;
    } else if (colors[1] == null) {
        return try std.fmt.allocPrint(alloc, "{s}", .{try colorToString(colors[0])});
    } else {
        return try std.fmt.allocPrint(alloc, "{s}-{s}", .{ try colorToString(colors[0]), try colorToString(colors[1]) });
    }
}

pub fn readTournamentList(alloc: std.mem.Allocator, payload_string: []u8) ![]game.Tournament {
    return try std.json.parseFromSlice([]game.Tournament, alloc, payload_string, .{});
}
