const std = @import("std");
const sio = @import("sio.zig");
const util = @import("util.zig");
const json_parse = @import("json_parse.zig");
const main = @import("main.zig");
pub const Color = enum(u32) { red = 0, green = 1, blue = 2, yellow = 3, noColor = 4 };

pub const CardType = enum { oneColor, twoColor, restart, view, select, joker };

pub const PlayerTypeTag = enum { localAi, external, localHuman };

pub const MoveType = enum { put, take, nope };

pub const PlayerHand = union(PlayerTypeTag) { localAi: Hand, external: usize, localHuman: Hand };

pub const GameError = error{InvalidCard};

pub const Player = struct {
    id: []const u8,
    username: []const u8,
    handSize: usize,
};

pub const TournamentListPlayer = struct {
    username: []const u8,

    pub fn format(value: TournamentListPlayer, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("🙋 {s}", .{value.username});
    }
};

pub const Card = struct {
    cardType: CardType,
    colors: [2]?Color,
    number: u32,

    pub fn fromServerInfo(server_card: json_parse.CardServerData) !Card {
        var card_type: ?CardType = null;
        var colors = [2]?Color{ null, null };

        if (server_card.color) |color| {
            colors = try json_parse.readStringColors(color);

            if (std.mem.eql(u8, "number", server_card.type)) {
                if (colors[1] == null) {
                    card_type = CardType.oneColor;
                } else {
                    card_type = CardType.twoColor;
                }

                return Card{
                    .cardType = card_type orelse return error.InvalidCard,
                    .colors = colors,
                    .number = server_card.value orelse 0, //NOTE: This is weird
                };
            }
        }
        if (std.mem.eql(u8, "joker", server_card.type)) {
            card_type = CardType.joker;
        } else if (std.mem.eql(u8, "reboot", server_card.type)) {
            card_type = CardType.restart;
        } else if (std.mem.eql(u8, "see-through", server_card.type)) {
            card_type = CardType.view;
        }
        return Card{
            .cardType = card_type orelse return error.InvalidCard,
            .colors = colors,
            .number = server_card.value orelse 0, //NOTE: This is weird
        };
    }
};

pub const Hand = struct {
    cards: std.ArrayList(Card),
};

pub const Deck = struct {
    const DeckCardCount: usize = 20 + 66 + 14 + 4;
    cards: [DeckCardCount]Card,
};

pub const Move = struct {
    move_type: MoveType,
    cards: [3]?Card,
    reason: []const u8,
};

pub const PlayerIdentity = struct { id: []const u8, username: []const u8 };

pub const GameState = struct {
    match_id: []const u8,
    game_id: []const u8,
    top_card: Card,
    last_top_card: ?Card,
    draw_pile_size: usize,
    players: []Player,
    own_hand: Hand,
    hand_size: usize,
    current_player: PlayerIdentity,
    current_player_index: u64,
    prev_player: ?PlayerIdentity,
    prev_plazer_index: ?u64,
    prev_turn_cards: std.ArrayList(Card),
    last_move: ?Move,

    pub fn getHandCardCount(self: *GameState) usize {
        return self.own_hand.cards.items.len;
    }
};

pub const Game = struct {
    game_state: ?GameState,
    tournament_list: ?std.ArrayList(Tournament),
    is_in_tournament: bool = false,
};

pub const Tournament = struct {
    id: []const u8,
    createdAt: []const u8,
    status: []const u8,
    currentSize: u64,
    players: []TournamentListPlayer,

    pub fn format(value: Tournament, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("Tournament: ( ", .{});
        for (value.players) |player| {
            try writer.print("{} ", .{player});
        }
        try writer.print(")", .{});
    }
};

pub fn makeDeck() [104]Card {
    comptime {
        const deck_card_count = 20 + 66 + 14 + 4;
        const colorType = @typeInfo(Color);
        var colorsDone = [_]Color{Color.noColor} ** 4;
        var deck_cards: [deck_card_count]Card = undefined;
        var current_index: u32 = 0;
        for (colorType.Enum.fields) |f| {
            if (f.value != 4) {
                // one-colored cards
                const card1 = Card{
                    .cardType = CardType.oneColor,
                    .colors = [_]?Color{ @intToEnum(Color, f.value), null },
                    .number = 1,
                };
                const card2 = Card{
                    .cardType = CardType.oneColor,
                    .colors = [_]?Color{ @intToEnum(Color, f.value), null },
                    .number = 2,
                };
                const card3 = Card{
                    .cardType = CardType.oneColor,
                    .colors = [_]?Color{ @intToEnum(Color, f.value), null },
                    .number = 3,
                };

                deck_cards[current_index] = card1;
                deck_cards[current_index + 1] = card1;
                current_index += 2;

                deck_cards[current_index] = card2;
                deck_cards[current_index + 1] = card2;
                current_index += 2;

                deck_cards[current_index] = card3;
                current_index += 1;
            }
        }

        for (colorType.Enum.fields) |f| {
            if (f.value != 4) {
                if (!std.mem.containsAtLeast(Color, &colorsDone, 1, &.{@intToEnum(Color, f.value)})) {
                    // TOODO two-colored cards
                    const card1 = Card{
                        .cardType = CardType.oneColor,
                        .colors = [_]?Color{ @intToEnum(Color, f.value), null },
                        .number = 1,
                    };
                    const card2 = Card{
                        .cardType = CardType.oneColor,
                        .colors = [_]?Color{ @intToEnum(Color, f.value), null },
                        .number = 2,
                    };
                    const card3 = Card{
                        .cardType = CardType.oneColor,
                        .colors = [_]?Color{ @intToEnum(Color, f.value), null },
                        .number = 3,
                    };

                    deck_cards[current_index] = card1;
                    deck_cards[current_index + 1] = card1;
                    current_index += 2;

                    deck_cards[current_index] = card2;
                    deck_cards[current_index + 1] = card2;
                    current_index += 2;

                    deck_cards[current_index] = card3;
                    current_index += 1;
                }

                colorsDone[f.value] = @intToEnum(Color, f.value);
            }
        }
        return deck_cards;
    }
}

pub fn makeMove(alloc: std.mem.Allocator, game_state: *const GameState, socket: *sio.SocketIO, event: *const sio.EventData, context: *main.App) !void {
    var move = Move{ .move_type = MoveType.put, .cards = [_]?Card{null} ** 3, .reason = "42" };
    const playable_cards = try getPlayableCards(alloc, game_state.own_hand, game_state.top_card);

    if (playable_cards.items.len >= game_state.top_card.number) {
        for (0..game_state.top_card.number) |i| {
            move.cards[i] = playable_cards.items[i];
        }
        move.move_type = MoveType.put;
    } else if (game_state.last_move) |last_move| {
        if (last_move.move_type == MoveType.take) {
            move.move_type = MoveType.nope;
        } else {
            move.move_type = MoveType.take;
        }
    }

    // TODO ACK BASTELN
    const card1 = if (move.cards[0]) |card|
        .{
            .type = "number",
            .color = try json_parse.colorsToCombinedString(alloc, card.colors),
            .value = card.number,
            //.select = null,
            //.selectValue = null,
            //.selectedColor = null,
        }
    else
        null;
    const card2 = if (move.cards[1]) |card|
        .{
            .type = "number",
            .color = try json_parse.colorsToCombinedString(alloc, card.colors),
            .value = card.number,
            //.select = null,
            //.selectValue = null,
            //.selectedColor = null,
        }
    else
        null;
    const card3 = if (move.cards[2]) |card|
        .{
            .type = "number",
            .color = try json_parse.colorsToCombinedString(alloc, card.colors),
            .value = card.number,
            //.select = null,
            //.selectValue = null,
            //.selectedColor = null,
        }
    else
        null;
    const payload_string = try std.json.stringifyAlloc(alloc, .{ .type = @tagName(move.move_type), .card1 = card1, .card2 = card2, .card3 = card3, .reason = move.reason }, .{});
    context.notify("Sending card: {s}\n", .{payload_string});

    const payload = sio.Payload{ .String = util.RustString.from_slice(payload_string) };
    socket.client.ack_message(event.id.?, payload);
}

pub fn getPlayableCards(alloc: std.mem.Allocator, hand: Hand, top_card: Card) !std.ArrayList(Card) {
    // only for color-cards, action-cards not included yet
    var playable_cards = std.ArrayList(Card).init(alloc);
    for (hand.cards.items) |f| {
        if (f.cardType == CardType.oneColor) {
            if (f.colors[0] == top_card.colors[0] or f.colors[0] == top_card.colors[1]) {
                try playable_cards.append(f);
            }
        } else if (f.cardType == CardType.twoColor) {
            if (f.colors[0] == top_card.colors[0] or f.colors[0] == top_card.colors[1] or
                f.colors[1] == top_card.colors[0] or f.colors[1] == top_card.colors[1])
            {
                try playable_cards.append(f);
            }
        }
    }
    return playable_cards;
}
