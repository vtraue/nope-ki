const std = @import("std");
const sio = @import("sio.zig");
const util = @import("util.zig");
const json_parse = @import("json_parse.zig");
const main = @import("main.zig");
const defs = @import("ai_defs.zig");

pub const Color = enum {
    red,
    green,
    blue,
    yellow,
    noColor,
    multi,
    pub fn matches(col1: Color, col2: Color) bool {
        if (col1 == Color.noColor or col2 == Color.noColor) {
            return false;
        }
        return ((col1 == col2) or col1 == Color.multi or col2 == Color.multi);
    }

    pub fn format(value: Color, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        try writer.print("{s}", .{@tagName(value)});
    }
};

pub const CardType = enum {
    oneColor,
    twoColor,
    restart,
    view,
    select,
    joker,
    pub fn format(value: CardType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        try writer.print("{s}", .{@tagName(value)});
    }
};

pub const PlayerTypeTag = enum { localAi, external, localHuman };

pub const MoveType = enum { put, take, nope };

pub const PlayerHand = union(PlayerTypeTag) { localAi: Hand, external: usize, localHuman: Hand };

pub const GameError = error{InvalidCard};

pub const Player = struct {
    handSize: usize,
    id: []const u8,
    username: []const u8,

    pub fn format(value: Player, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("username: {s}, ", .{value.username});
        try writer.print("handsize: {} ", .{value.handSize});
    }
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
    priority: u32 = 3,

    const ServerJokerValue = 1;
    const LocalJokerValue = 4;

    pub fn prioSort(context: *const GameState, lhs: Card, rhs: Card) bool {
        _ = context;
        return lhs.priority > rhs.priority;
    }

    pub fn fromServerInfo(server_card: json_parse.CardServerData) !Card {
        var card_type: ?CardType = null;
        var colors = [2]?Color{ null, null };

        if (server_card.color) |color| {
            colors = try json_parse.readStringColors(color);

            if (std.mem.eql(u8, "number", server_card.type)) {
                if (colors[1] != null) {
                    card_type = CardType.twoColor;
                } else {
                    card_type = CardType.oneColor;
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

    pub fn cardToServer(card: Card, alloc: std.mem.Allocator) !json_parse.CardServerData {
        var number: ?u32 = null;
        if (card.cardType == CardType.oneColor or card.cardType == CardType.twoColor or card.cardType == CardType.joker) {
            number = card.number;
        }
        var server_card: json_parse.CardServerData =
            .{
            .type = try cardTypeToServer(card.cardType),
            .color = try json_parse.colorsToCombinedString(alloc, card.colors),
            .value = number,
        };
        return server_card;
    }

    pub fn cardTypeToServer(cardType: CardType) ![]const u8 {
        switch (cardType) {
            .oneColor, .twoColor => {
                return "number";
            },
            .restart => {
                return "reboot";
            },
            .view => {
                return "see-through";
            },
            .select => {
                return "selection";
            },
            .joker => {
                return "joker";
            },
        }
    }

    pub inline fn isPureColorCard(self: *const Card) bool {
        return (self.cardType == CardType.oneColor or self.cardType == CardType.twoColor);
    }

    pub inline fn isColorCard(self: *const Card) bool {
        return (self.isPureColorCard() or self.cardType == CardType.view or self.cardType == CardType.select or self.cardType == CardType.joker);
    }

    pub inline fn isActionCard(self: *const Card) bool {
        return (!self.isPureColorCard());
    }

    pub inline fn hasColor(self: *const Card, color: Color) bool {
        if (!self.isColorCard()) {
            return false;
        }

        if (self.cardType == CardType.twoColor) {
            return (Color.matches(color, self.colors[0].?) or Color.matches(color, self.colors[1].?));
        } else {
            return (Color.matches(color, self.colors[0].?));
        }
    }
    pub inline fn isOneColor(self: *const Card) bool {
        return (self.cardType == CardType.oneColor or self.colors[1] == null);
    }

    pub inline fn isTwoColor(self: *const Card) bool {
        return (self.cardType == CardType.twoColor or self.colors[1] != null);
    }
    pub inline fn isUseless(self: *const Card) bool {
        return (self.cardType == CardType.restart or self.cardType == CardType.view);
    }

    pub fn setDefaultPrio(self: *Card, opponent_hand_size: usize, last_top_card: ?Card) !void {
        // prio special meanings:
        // 10 - play it as next top card
        //  9 - get rid of it, but not as top card
        //  1 - keep it if possible
        switch (self.cardType) {
            // jokers are bad, get rid of them
            .joker => {
                self.priority = 9;
            },
            // we can use view cards to let the opponent play on a number 1 card, if he has only one card left, so keep it
            .view => {
                self.priority = 1;
            },
            // wen can make the opponent play his last card with reboot, so keep it
            .restart => {
                self.priority = 1;
            },
            // one-colored cards are not that "bad" as two-colored for completing sets
            .oneColor => {
                self.priority = 4;
            },
            // so two-colored cards have a higher priority to get rid of them, than one-colored cards
            .twoColor => {
                self.priority = 7;
            },
            else => {},
        }
        // adjustments, if the opponent more than 5 cards on hand
        if (opponent_hand_size > 5 and self.cardType != CardType.joker) {
            switch (self.number) {
                // play less low numbered cards
                1 => {
                    self.priority -= 1;
                },
                // and morge high numbered cards, bceause the chance that the opponent can serve a 3 is higher
                3 => {
                    self.priority += 1;
                },
                else => {},
            }
        }

        // adjustment, if the opponent has less than 6 cards on hand
        if (opponent_hand_size <= 5 and self.cardType != CardType.joker) {
            switch (self.number) {
                // play more low numbered cards
                1 => {
                    self.priority += 1;
                },
                // and less high numbered cards, because the chance that the opponent can't serve a 3 is high
                3 => {
                    self.priority -= 1;
                },
                else => {},
            }
        }
        if (opponent_hand_size == 1) {
            switch (self.cardType) {
                // opponent has to play his last card onto the reboot card, so play it!
                .restart => {
                    self.priority = 10;
                },
                // opponent has to play his last card onto the joker, so play it as top card!
                .joker => {
                    self.priority = 10;
                },
                // opponent has to play his last card onto the last topcard, if its a number 1 or a joker (which has 1 as number)
                .view => {
                    if (last_top_card) |n| {
                        if (n.number == 1) {
                            self.priority = 10;
                        }
                    }
                },
                else => {},
            }
            switch (self.number) {
                // 25% chance, that the opponent has to play his last card, so play it as top card!
                1 => {
                    self.priority = 10;
                },
                else => {},
            }
        }
    }

    pub fn format(value: Card, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        try writer.print("type: {},  ", .{value.cardType});
        try writer.print("colors: {any},  ", .{value.colors});
        try writer.print("number: {}, ", .{value.number});
        try writer.print("priority: {} ", .{value.priority});
    }
};

pub const Hand = struct {
    cards: std.ArrayList(Card),

    pub fn format(value: Hand, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        for (value.cards.items) |card| {
            try writer.print("\n{}", .{card});
        }
    }
};

pub const Deck = struct {
    const DeckCardCount: usize = 20 + 66 + 14 + 4;
    cards: [DeckCardCount]Card,
};

pub const Move = struct {
    move_type: MoveType,
    cards: [3]?Card,
    reason: []const u8 = "no reason",

    pub fn format(value: Move, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("Making Move: {}\n", .{value.move_type});
        for (value.cards) |card| {
            if (card) |c| {
                try writer.print("Card: {any}\n", .{c});
            }
        }
    }
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
    prev_player_index: ?u64,
    prev_turn_cards: std.ArrayList(Card),
    last_move: ?Move,
    opponent_hand_size: usize,

    //TODO: Explain later
    pub fn getPlayableTopCard(self: *const GameState) Card {
        return blk: {
            if (self.top_card.cardType == CardType.view) {
                var new_card = self.last_top_card.?;

                if (new_card.cardType == CardType.view) {
                    return Card{ .colors = new_card.colors, .number = 1, .cardType = CardType.oneColor };
                } else {
                    break :blk new_card;
                }
            } else {
                break :blk self.top_card;
            }
        };
    }

    pub fn getHandCardCount(self: *GameState) usize {
        return self.own_hand.cards.items.len;
    }

    pub fn format(value: GameState, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        try writer.print("draw_pile_size: {}\n", .{value.draw_pile_size});
        try writer.print("current_player: {}\n", .{value.players[value.current_player_index]});
        if (value.prev_player_index) |i| {
            try writer.print("prev_player: {}\n", .{value.players[i]});
        }
        try writer.print("prev_turn_cards: ", .{});
        for (value.prev_turn_cards.items) |card| {
            try writer.print("{}, ", .{card});
        }
        try writer.print("\n", .{});
        try writer.print("last_move: {?}", .{value.last_move});
        try writer.print("opponent_hand_size: {any}\n", .{value.opponent_hand_size});
        try writer.print("own_hand_size: {}\n", .{value.hand_size});
        try writer.print("own_hand: {any}\n", .{value.own_hand});
        try writer.print("last_top_card: {?}\n", .{value.last_top_card});
        try writer.print("top_card: {any}\n", .{value.top_card});
    }
};

pub const Game = struct {
    game_state: ?GameState = null,
    tournament_list: ?[]Tournament = null,
    is_in_tournament: bool = false,
};

pub const Tournament = struct {
    createdAt: []const u8,
    currentSize: u64,
    id: []const u8,
    players: []TournamentListPlayer,
    status: []const u8,

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

pub fn playSingleCard(alloc: std.mem.Allocator, card: Card, socket: *sio.SocketIO, event: *const sio.EventData) !void {
    const server_card = try Card.cardToServer(card, alloc);
    const payload_string = try std.json.stringifyAlloc(alloc, .{ .type = @tagName(MoveType.put), .card1 = server_card, .card2 = null, .card3 = null, .reason = "Getting rid of useless action cards" }, .{});

    //std.debug.print("raw json Move: {s}\n", .{payload_string});
    std.debug.print("\nI played: {}\n", .{card});
    const payload = sio.Payload{ .String = util.RustString.from_slice(payload_string) };

    socket.client.ack_message(event.id.?, payload);
}

pub const RiskResult = struct { risk: u32, cardIndex: u32 };

pub fn getLowestRiskCardIndex(alloc: std.mem.Allocator, cards: []Card, hand: []Card) !RiskResult {
    var best: u32 = 0;
    var lowest_danger: u32 = 255;
    for (0.., cards) |i, c| {
        const playable_count = try CardFilterIterator.countPlayableCards(alloc, hand, &c);
        const danger = if (playable_count >= c.number) c.number else 0;
        if (danger < lowest_danger) {
            lowest_danger = danger;
            best = @intCast(u32, i);
        }
    }

    return RiskResult{ .risk = lowest_danger, .cardIndex = best };
}

pub fn getHighestPrioIndex(cards: []Card) usize {
    var prio: u32 = 0;
    var best: usize = 0;

    for (0.., cards) |i, c| {
        if (c.priority > prio) {
            best = i;
        }
    }
    return best;
}

pub fn chooseMoveCards(alloc: std.mem.Allocator, move: *Move, deck: []Card, playable_cards: []Card, count: u32, opponent_hand_size: usize) !void {
    var temp_arr = try alloc.alloc(Card, count);
    const top_card_index = count - 1;

    //0 1 2
    for (0..count) |i| {
        move.cards[top_card_index - i] = playable_cards[i];
        temp_arr[top_card_index - i] = playable_cards[i];
    }

    var playSafe: bool = false;
    if (defs.chooseTopCardByRisk and defs.playRiskyWhenEnemeyAt > 0) {
        if (opponent_hand_size >= defs.playRiskyWhenEnemeyAt) {
            playSafe = false;
        } else {
            if (deck.len <= defs.playSafeWhenHandAt) {
                playSafe = true;
                std.debug.print("Playing safe\n", .{});
            }
        }
    }

    if (playSafe) {
        const risk_result = try getLowestRiskCardIndex(alloc, temp_arr, deck);
        const new_top_card = temp_arr[risk_result.cardIndex];
        std.debug.print("Lowest risk card: {}\n", .{new_top_card});
        if (move.cards[top_card_index]) |old| {
            move.cards[risk_result.cardIndex] = old;
        }
        move.cards[top_card_index] = new_top_card;
    } else {
        std.debug.print("Not playing safe\n", .{});
    }
}
pub fn chooseColorToPlay(all_cards: [][]Card, top: *const Card) []Card {
    const count = top.number;
    var best_sum: u32 = 999;
    var result = all_cards[0];

    for (0.., all_cards) |i, arr| {
        _ = i;
        if (arr.len >= count) {
            var prio_sum: u32 = 0;
            for (0..count) |ic| {
                prio_sum += arr[ic].priority;
            }
            if (prio_sum < best_sum) {
                best_sum = prio_sum;
                result = arr;
            }
        }
    }
    return result;
}

pub fn makeMove(alloc: std.mem.Allocator, game_state: *const GameState, socket: *sio.SocketIO, event: *const sio.EventData) !void {
    const top_card = game_state.getPlayableTopCard();
    const count = top_card.number;
    _ = count;

    for (game_state.own_hand.cards.items) |card| {
        if (card.cardType == CardType.restart) {
            try playSingleCard(alloc, card, socket, event);
            return;
        } else if (card.cardType == CardType.view and top_card.hasColor(card.colors[0].?)) {
            try playSingleCard(alloc, card, socket, event);
            return;
        }
    }

    var move = Move{ .move_type = MoveType.take, .cards = [_]?Card{null} ** 3, .reason = "42" };

    const playable_card_arr = try getPlayableCards(alloc, &game_state.own_hand, game_state);

    var playable_cards = playable_card_arr[0];
    if (defs.chooseColorBySumOfPrio) {
        playable_cards = chooseColorToPlay(playable_card_arr, &top_card);
    } else {
        for (0.., playable_card_arr) |i, arr| {
            _ = i;
            if (arr.len > playable_cards.len) {
                playable_cards = arr;
            }
        }
    }

    if (defs.sortCardsByPrio) {
        std.sort.insertion(Card, playable_cards, game_state, Card.prioSort);
    }
    std.debug.print("Playable cards:\n", .{});

    for (playable_cards) |c| {
        std.debug.print("{}\n", .{c});
    }

    if (top_card.colors[0] == Color.multi and playable_cards.len >= 1) {
        // play any card (make a smart choice later)
        move.cards[0] = playable_cards[0];
        move.move_type = MoveType.put;
    } else if (playable_cards.len >= top_card.number) {
        try chooseMoveCards(alloc, &move, game_state.own_hand.cards.items, playable_cards, top_card.number, game_state.opponent_hand_size);
        move.move_type = MoveType.put;
    } else if (game_state.last_move) |last_move| {
        if (last_move.move_type == MoveType.take) {
            move.move_type = MoveType.nope;
        }
    }

    const card1 = if (move.cards[0]) |card| try Card.cardToServer(card, alloc) else null;

    const card2 = if (move.cards[1]) |card| try Card.cardToServer(card, alloc) else null;

    const card3 = if (move.cards[2]) |card| try Card.cardToServer(card, alloc) else null;

    const payload_string = try std.json.stringifyAlloc(alloc, .{ .type = @tagName(move.move_type), .card1 = card1, .card2 = card2, .card3 = card3, .reason = move.reason }, .{});
    //std.debug.print("raw json Move: {s}\n", .{payload_string});
    std.debug.print("I played: {}\n", .{move});
    const payload = sio.Payload{ .String = util.RustString.from_slice(payload_string) };
    socket.client.ack_message(event.id.?, payload);
}

pub const ColorFilter = union(enum) {
    Has: Color,
    Any: void,
    OneColor: void,
    TwoColor: void,
    NoColor: void,
};

pub const ValueFilter = union(enum) {
    Only: u32,
};

pub const TypeFilter = union(enum) {
    Only: CardType,
    ActionCard: void,
};

pub const Filter = struct {
    color: ?ColorFilter = null,
    value: ?ValueFilter = null,
    cardType: ?TypeFilter = null,

    pub fn isCardAllowed(filter: *const Filter, card: *const Card) bool {
        const is_color_okay = blk: {
            if (filter.color) |col| {
                break :blk switch (col) {
                    .Any => true,
                    .Has => |c| card.hasColor(c),
                    .OneColor => card.isOneColor(),
                    .TwoColor => card.isTwoColor(),
                    .NoColor => !card.isColorCard(),
                };
            } else {
                break :blk true;
            }
        };

        if (!is_color_okay) return false;

        const is_value_okay = blk: {
            if (filter.value) |val| {
                break :blk (card.number == val.Only);
            } else break :blk true;
        };
        if (!is_value_okay) return false;

        const is_type_okay = blk: {
            if (filter.cardType) |typ| {
                break :blk switch (typ) {
                    .Only => |t| card.cardType == t,
                    .ActionCard => card.isActionCard(),
                };
            }
            break :blk true;
        };

        return is_type_okay;
    }
};

pub const CardFilterIterator = struct {
    hand: []Card,
    position: usize = 0,

    //TODO: Maybe let filter by more colors
    filter: ?Filter,

    //TODO: Card category

    pub fn isCardAllowed(self: *const CardFilterIterator, card: *const Card) bool {
        if (self.filter) |filter| {
            return Filter.isCardAllowed(&filter, card);
        } else {
            return true;
        }
    }

    pub fn next(self: *CardFilterIterator) ?Card {
        if (self.hand.len == 0) {
            return null;
        }

        while (self.position < self.hand.len) : (self.position += 1) {
            const currentCard = self.hand[self.position];
            if (self.isCardAllowed(&currentCard)) {
                self.position += 1;
                return currentCard;
            }
        }

        return null;
    }

    pub fn count(self: *CardFilterIterator) u32 {
        var i: u32 = 0;
        while (self.next()) |card| {
            _ = card;
            i += 1;
        }
        return i;
    }

    pub fn collect(self: *CardFilterIterator, alloc: std.mem.Allocator) ![]Card {
        var deck = std.ArrayList(Card).init(alloc);

        while (self.next()) |card| {
            try deck.append(card);
        }
        return deck.items;
    }

    pub fn collectMultiple(alloc: std.mem.Allocator, filters: []Filter, cards: []Card) ![][]Card {
        var iter = CardFilterIterator{ .filter = filters[0], .hand = cards };

        var arr = std.ArrayList([]Card).init(alloc);

        for (filters) |f| {
            iter.filter = f;
            try arr.append(try iter.collect(alloc));
            iter.reset();
        }
        return arr.items;
    }

    pub fn reset(self: *CardFilterIterator) void {
        self.position = 0;
    }

    pub const PlayableCards = union(enum) { OneColor: []Card, TwoColor: struct { []Card, []Card } };

    pub const CardGetMoveError = error{UnexpectedCardHasNoColor};

    pub fn getPlayableCards(alloc: std.mem.Allocator, hand: *const Hand, state: *const GameState) ![][]Card {
        const filters = try matchingFilterFromState(alloc, state);
        var arr = try CardFilterIterator.collectMultiple(alloc, filters, hand.cards.items);
        return arr;
    }

    pub fn countPlayableCards(alloc: std.mem.Allocator, hand: []Card, card: *const Card) !u32 {
        const filters = try filtersFromCard(alloc, card);
        defer alloc.free(filters);

        var iter = CardFilterIterator{ .filter = filters[0], .hand = hand };
        var result: u32 = 0;

        for (filters) |f| {
            iter.filter = f;
            var i = iter.count();

            //TODO: Maybe make this smarter?
            if (i > result) {
                result = i;
            }

            iter.reset();
        }
        return result;
    }
};

pub fn filtersFromCard(alloc: std.mem.Allocator, card: *const Card) ![]Filter {
    var filters = std.ArrayList(Filter).init(alloc);
    try filters.append(.{ .color = .{ .Has = card.colors[0] orelse return error.UnexpectedCardHasNoColor } });

    if (card.cardType == .twoColor) {
        try filters.append(.{ .color = .{ .Has = card.colors[1] orelse return error.UnexpectedCardHasNoColor } });
    }

    return filters.items;
}

pub fn matchingFilterFromState(alloc: std.mem.Allocator, state: *const GameState) ![]Filter {
    const top_card = state.getPlayableTopCard();
    return filtersFromCard(alloc, &top_card);
}

pub fn getPlayableCards(alloc: std.mem.Allocator, hand: *const Hand, state: *const GameState) ![][]Card {
    return CardFilterIterator.getPlayableCards(alloc, hand, state);
}

pub fn handleActionCard(alloc: std.mem.Allocator, hand: Hand, top_card: Card, last_top_card: Card) !void {
    switch (top_card.cardType) {
        .restart => {
            //play "best" card from hand, any color
        },
        .view => {
            getPlayableCards(alloc, hand, last_top_card);
        },
        .joker => {
            //play "best" card from hand, any color
        },
        .select => {},
        else => unreachable,
    }
}
