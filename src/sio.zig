const std = @import("std");
const c = @import("sio_c.zig");
const util = @import("util.zig");

pub const EventTypeTag = enum(c_uint) { Message = 0, Error = 1, Custom = 2, Connect = 3, Close = 4 };

pub const EventType = union(EventTypeTag) {
    Message: void,
    Error: void,
    Custom: util.RustString,
    Connect: void,
    Close: void,

    fn to_rust(self: *const EventType) c.SioEvent {
        var event: c.SioEvent = undefined;
        var tag = @enumToInt(@as(EventTypeTag, self.*));

        event.tag = @as(c_uint, tag);
        switch (self.*) {
            .Custom => |str| {
                event.unnamed_0.unnamed_0.custom = str.inner;
            },
            else => {},
        }
        return event;
    }

    fn from_rust(ev: c.SioEvent) EventType {
        return switch (ev.tag) {
            c.Custom => {
                return EventType{ .Custom = util.RustString.from_rust(c.sio_event_string(&ev)) };
            },
            c.Message => return EventType.Message,
            c.Error => return EventType.Connect,
            c.Connect => return EventType.Close,
            else => unreachable,
        };
    }
};

pub fn blob_to_slice(blob: *const c.BinaryBlob) ?[]const u8 {
    if (blob.len == 0) {
        return null;
    }
    const raw_pointer = blob.data orelse return null;

    return @ptrCast([*]const u8, raw_pointer)[0..blob.len];
}

pub const PayloadTag = enum { Binary, String };
//TODO: Make Binary a more concrete type

pub const Payload = union(PayloadTag) {
    Binary: []const u8,
    String: util.RustString,

    fn from_rust(payload: c.SioPayload) Payload {
        return switch (payload.tag) {
            c.Binary => {
                const bin = c.sio_payload_bin(&payload);
                return Payload{ .Binary = blob_to_slice(&bin) orelse unreachable };
            },

            c.String => return Payload{ .String = util.RustString.from_rust(c.sio_payload_string(&payload)) },
            else => std.debug.panic("Invalid payload type", .{}),
        };
    }

    fn to_rust(self: *const Payload) c.SioPayload {
        return switch (self.*) {
            .Binary => |data| {
                const blob = c.BinaryBlob{ .data = @ptrCast(?*const anyopaque, data), .len = data.len };
                return c.new_binary_payload(blob);
            },

            .String => |str| {
                return c.new_string_payload(str.inner);
            },
        };
    }
};

pub const ClientParameters = struct {
    address: [:0]const u8,
    namespace: [:0]const u8 = "/",
    auth: ?[:0]const u8 = null,
    reconnect: bool = false,
    reconnect_delay_min: u32 = 0,
    reconnect_delay_max: u32 = 0,

    fn to_rust(self: *const ClientParameters, 
        user_data: ?* const anyopaque,
        callback: c.EventCallback,
        ack_callback: c.AckCallback,
        ack_user_data: ?* const anyopaque,
        ) c.ClientSettings {
        return c.ClientSettings{ 
            .address = self.address, 
            .namespace_ = self.namespace, 
            .reconnect = self.reconnect, 
            .reconnect_delay_min = self.reconnect_delay_min, 
            .reconnect_delay_max = self.reconnect_delay_max,
            .user_data = c.EventCallbackData {.data = user_data},
            .on = callback, 
            .auth = self.auth orelse 0,
            .on_ack = ack_callback,
            .on_ack_data = c.AckCallbackData {.data = ack_user_data}
        };
    }
};

pub const EmitData = struct {
    event: EventType,
    payload: ?Payload,
    should_ack: bool = true,
    ack_timeout_ms: u64 = 100000,

    pub fn to_rust(self: *const EmitData) c.SioEmitData {
        const event = self.event.to_rust();
        if(self.payload) |payload| {
            return c.SioEmitData{ .event = event, .has_payload = true, .payload = payload.to_rust(), .ack = self.should_ack, .ack_timeout = self.ack_timeout_ms};
        } else {
            const payload = Payload {.String = util.RustString.from_slice("SHOULD_BE_EMPTY")};
            return c.SioEmitData{ .event = event, .has_payload = false, .payload = payload.to_rust(), .ack = self.should_ack, .ack_timeout = self.ack_timeout_ms};
            
        }
    }
};

pub const Client = struct {
    inner: c.SioClient,
    parameters: ClientParameters,
    is_connected: bool = true,

    //TODO: Have bindings return error enums instead of just crashing
    pub fn connect(
        parameters: ClientParameters, 
        user_data: ?* const anyopaque, 
        callback: c.EventCallback,
        ack_callback: c.AckCallback,
        ack_user_data: ?* const anyopaque) Client {

        var client = c.sio_client_new(parameters.to_rust(user_data, callback, ack_callback, ack_user_data));
        return Client{ .inner = client, .parameters = parameters };
    }

    pub fn emit(self: *const Client, emit_data: EmitData) void {
        c.sio_client_emit(&self.inner, emit_data.to_rust());
    }

    pub fn ack_message(self: *const Client, message_id: i32, data: Payload) void {
        c.sio_client_ack(&self.inner, message_id, data.to_rust());
    }

    pub fn try_ack(self: *const Client, event: *const EventData, data: Payload) ?i32 {
        if(event.id) |id| {
            c.sio_client_ack(&self.inner, id, data.to_rust());
        }
        return event.id;
    }

    pub fn disonnect(self: *Client) void {
        c.sio_client_disconnect(&self.inner);
        self.is_connected = false;
    }
};

pub const RawClient = struct { inner: c.RawClient };

pub const EventData = struct {
    event: EventType,
    payload: Payload,

    id: ?i32,

    pub fn from_rust(data: c.SioEventData) EventData {
        const event = EventType.from_rust(data.event);
        const payload = Payload.from_rust(data.payload);

        var id: ?i32 = null;

        if(data.wants_ack) {
            id = data.message_id; 
        }
        return EventData{ .event = event, .payload = payload, .id = id};
    }
};

pub const SocketIO = struct {
    client: Client,

    events: *util.ThreadQueue(EventData),
    acks: *util.ThreadQueue(Payload),

    fn get_event(self: *const SocketIO) EventData {
        return self.events.block_pop_front();
    }

};

fn get_queue(comptime queue_type: type, data: anytype) *util.ThreadQueue(queue_type) {
    return @ptrCast(*util.ThreadQueue(queue_type), @alignCast(8, @constCast(data.data)));
}

pub fn inner_event_callback(event: [*c]const c.struct_SioEventData, user_data: c.EventCallbackData) callconv(.C) void {
    const event_ptr = @ptrCast(*const c.SioEventData, event);
    var queue = get_queue(EventData, user_data); 

    queue.push_back(EventData.from_rust(event_ptr.*)) catch |err| std.debug.print("Unable to push event: {}", .{err}); 
}

//TODO: Get pointer/copy of original event 
pub fn inner_ack_callback(message: [*c]const c.struct_SioPayload, user_data: c.AckCallbackData) callconv(.C) void {
    std.debug.print("ack!\n", .{});

    const payload_ptr = @ptrCast(*const c.SioPayload, message);
    var queue = get_queue(Payload, user_data); 

    queue.push_back(Payload.from_rust(payload_ptr.*)) catch |err| std.debug.print("Unable to push awk {}", .{err});
}

pub fn create_client(alloc: std.mem.Allocator, parameters: ClientParameters) !SocketIO {
    const queue_size = 512;

    var thread_queue = try alloc.create(util.ThreadQueue(EventData));
    thread_queue.* = try util.ThreadQueue(EventData).new(alloc, queue_size); 
    
    var ack_queue = try alloc.create(util.ThreadQueue(Payload));
    ack_queue.* = try util.ThreadQueue(Payload).new(alloc, queue_size); 

    var client = Client.connect(parameters, 
        thread_queue, 
        inner_event_callback, 
        inner_ack_callback, 
        ack_queue);

    return .{.client = client, .events = thread_queue, .acks = ack_queue};
}

