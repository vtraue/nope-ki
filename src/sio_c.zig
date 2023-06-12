pub const struct_RustString = extern struct {
    buf: [*c]u8,
    len: usize,
    capacity: usize,
};
pub const RustString = struct_RustString;
pub const struct_SioClient = extern struct { _inner: ?*const anyopaque, on_ack: AckCallback, on_ack_data: AckCallbackData };

pub const SioClient = struct_SioClient;
pub const Message: c_int = 0;
pub const Error: c_int = 1;
pub const Custom: c_int = 2;
pub const Connect: c_int = 3;
pub const Close: c_int = 4;
pub const enum_SioEvent_Tag = c_uint;

pub fn sio_event_string(ev: *const struct_SioEvent) struct_RustString {
    return ev.unnamed_0.unnamed_0.custom;
}

pub fn sio_payload_bin(payload: *const struct_SioPayload) struct_BinaryBlob {
    return payload.unnamed_0.unnamed_0.binary;
}

pub fn sio_payload_string(payload: *const struct_SioPayload) struct_RustString {
    return payload.unnamed_0.unnamed_1.string;
}

pub fn new_binary_payload(blob: struct_BinaryBlob) struct_SioPayload {
    var payload: struct_SioPayload = undefined;
    payload.tag = Binary;
    payload.unnamed_0.unnamed_0.binary = blob;
    return payload;
}

pub fn new_string_payload(string: struct_RustString) struct_SioPayload {
    var payload: struct_SioPayload = undefined;
    payload.tag = String;
    payload.unnamed_0.unnamed_1.string = string;
    return payload;
}

pub const SioEvent_Tag = enum_SioEvent_Tag;
const struct_unnamed_2 = extern struct {
    custom: struct_RustString,
};
const union_unnamed_1 = extern union {
    unnamed_0: struct_unnamed_2,
};
pub const struct_SioEvent = extern struct {
    tag: SioEvent_Tag,
    unnamed_0: union_unnamed_1,
};

pub const SioEvent = struct_SioEvent;
pub const struct_BinaryBlob = extern struct {
    data: ?*const anyopaque,
    len: usize,
};

pub const BinaryBlob = struct_BinaryBlob;
pub const Binary: c_int = 0;
pub const String: c_int = 1;
pub const enum_SioPayload_Tag = c_uint;
pub const SioPayload_Tag = enum_SioPayload_Tag;

const struct_unnamed_4 = extern struct {
    binary: struct_BinaryBlob,
};
const struct_unnamed_5 = extern struct {
    string: struct_RustString,
};
const union_unnamed_3 = extern union {
    unnamed_0: struct_unnamed_4,
    unnamed_1: struct_unnamed_5,
};
pub const struct_SioPayload = extern struct {
    tag: SioPayload_Tag,
    unnamed_0: union_unnamed_3,
};
pub const SioPayload = struct_SioPayload;
pub const struct_SioEmitData = extern struct { 
    event: struct_SioEvent, 
    has_payload: bool,
    payload: struct_SioPayload, 
    ack: bool, 
    ack_timeout: u64 };

pub const SioEmitData = struct_SioEmitData;
pub const struct_SioRawClient = extern struct {
    _inner: ?*const anyopaque,
};
pub const SioRawClient = struct_SioRawClient;

pub const struct_SioEventData = extern struct {
    event: struct_SioEvent,
    payload: struct_SioPayload,
    client: struct_SioRawClient,
    wants_ack: bool,
    message_id: i32
};

pub const EventCallbackData = extern struct { data: ?*const anyopaque };
pub const AckCallbackData = extern struct { data: ?*const anyopaque };

pub const SioEventData = struct_SioEventData;

pub const EventCallback = ?*const fn ([*c]const struct_SioEventData, EventCallbackData) callconv(.C) void;
pub const AckCallback = ?*const fn ([*c]const struct_SioPayload, AckCallbackData) callconv(.C) void;

pub const struct_ClientSettings = extern struct { address: [*c]const u8, namespace_: [*c]const u8, auth: [*c]const u8, reconnect: bool, reconnect_delay_min: u64, reconnect_delay_max: u64, on: EventCallback, user_data: EventCallbackData, on_ack: AckCallback, on_ack_data: AckCallbackData };

pub const ClientSettings = struct_ClientSettings;
pub extern fn rust_add_stuff(a: usize, b: usize) usize;
pub extern fn rust_hello() void;
pub extern fn rust_string_free(old_string: [*c]struct_RustString) void;
pub extern fn rust_string_new(initial_size: usize) struct_RustString;
pub extern fn rust_string_resize(old_string: [*c]struct_RustString, additional: usize) struct_RustString;
pub extern fn sio_client_emit(client: [*c]const struct_SioClient, data: struct_SioEmitData) void;
pub extern fn sio_client_disconnect(clinet: [*c]const struct_SioClient) void;
pub extern fn sio_client_free(client: [*c]struct_SioClient) void;
pub extern fn sio_client_ack(client: [*c]const struct_SioClient, message_id: i32, data: struct_SioPayload) void;
pub extern fn sio_client_new(settings: struct_ClientSettings) struct_SioClient;
