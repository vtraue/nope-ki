const std = @import("std");

const c = @cImport({
    @cInclude("curl.h");
});

pub const CurlError = error {
    UnableToInit,
    UnableToSetUrl,
    UnableToSetOption,
    InvalidOptionType
};

fn c_bool(val: bool) c_ulong {
    return @as(c_ulong, if(val) 1 else 0);
}
fn tryCurl(code: c.CURLcode) CurlError!void {
    if(code != c.CURLE_OK) {
        //std.debug.print("Unable to do curl op, error code: {}", .{code});
        return error.UnableToSetOption;
    }
}

pub const RequestTypeTag = enum {
    Get,
    Post,
    Upload,

    pub fn as_curl_op(self: *const RequestTypeTag) c.CURLoption {
        return switch (self.*) {
            .Get => c.CURLOPT_HTTPGET,
            .Post => c.CURLOPT_POST,
            .Upload => c.CURLOPT_UPLOAD
        };
    }
};

pub const RequestType = union(RequestTypeTag) {
    Get: void,
    Post: []const u8,
    Upload: []const u8, 

    pub fn as_curl_op(self: *const RequestType) c.CURLoption {
        return @as(RequestTypeTag, self.*).as_curl_op();
    }
};

pub const Request = struct {
    header_list: ?*c.curl_slist = null,

    url: [:0]const u8,
    ssl: SSLOptions = .{},
    user_agent: [:0]const u8 = "curl/8.0.1",
    max_redirs: u64 = 50,
    show_progress: bool = false,
    content_type: [:0]const u8 = "application/json",
    request_type: RequestType = RequestType.Get, 
    verbose_log: bool = true
};

pub const SSLOptions = struct {
    peer_verification: bool = false,
    hostname_verification: bool = false,

    pub fn set_options(self: *const SSLOptions, curl: *CurlHandle) !void{
        try curl.set_options(.{
            .{c.CURLOPT_SSL_VERIFYPEER, self.peer_verification},
            .{c.CURLOPT_SSL_VERIFYHOST, self.hostname_verification}
        });
    }
};

pub const Response = struct {
    status_code: c_long,
    http_version: c_long,
    content_type: [:0]u8,

    data: std.ArrayList(u8),
    
    pub fn from_curl(curl: *CurlHandle, data: std.ArrayList(u8)) !Response {
        //std.debug.print("parsing response\n", .{});
        var response: Response = undefined;

        var content_type_str: [*c]u8 = undefined;
        try tryCurl(c.curl_easy_getinfo(curl.curl_handle, c.CURLINFO_RESPONSE_CODE, &response.status_code));
        try tryCurl(c.curl_easy_getinfo(curl.curl_handle, c.CURLINFO_HTTP_VERSION, &response.http_version));
        try tryCurl(c.curl_easy_getinfo(curl.curl_handle, c.CURLINFO_CONTENT_TYPE, &content_type_str));

        response.content_type = std.mem.span(content_type_str);

        response.data = data;
        //std.debug.print("response: {}\n", .{response});
        //std.debug.print("done\n", .{});
        return response;

    }
};
fn write_to_array_list_callback(data: *anyopaque, size: c_uint, nmemb: c_uint, user_data: *anyopaque) callconv(.C) c_uint{
    //std.debug.print("writing\n", .{});
    var buffer = @intToPtr(*std.ArrayList(u8), @ptrToInt(user_data));
    var real_data = @intToPtr([*]u8, @ptrToInt(data));

    buffer.appendSlice(real_data[0.. nmemb * size]) catch return 0;
    //std.debug.print("writing done\n", .{});
    return nmemb * size;
}

pub const CurlHandle = struct {
    curl_handle: *c.CURL,
    
    pub fn init() CurlError!CurlHandle {
        const handle = @ptrCast(?*c.CURL, c.curl_easy_init()) orelse return error.UnableToInit;
        return CurlHandle {.curl_handle = handle};
    }

    pub fn set_opt(self: *CurlHandle, option: anytype, parameter: anytype) CurlError!void {
        const parameter_type = @TypeOf(parameter);
        const option_type = @TypeOf(option);
        var option_value: c.CURLoption = undefined;

        const is_valid_type = comptime switch (option_type) {
            c_uint, c_int => true,
            else => false
        };

        if(!is_valid_type) {
            if (comptime std.meta.trait.hasFn("as_curl_op")(option_type)) {
                option_value = option.as_curl_op(); 
            } else {
                @compileError("Missing function: as_curl_op on " ++ @typeName(option_type));
            } 
        } else {
            option_value = @intCast(c.CURLoption, option);
        }

        if(comptime std.meta.trait.isZigString(parameter_type)) {
            const str = @as([]const u8, parameter);
            return tryCurl(c.curl_easy_setopt(self.curl_handle, option_value, str.ptr));
        } else {
            switch (parameter_type) {
                bool => return tryCurl(c.curl_easy_setopt(self.curl_handle, option_value, c_bool(parameter))),

                else => return tryCurl(c.curl_easy_setopt(self.curl_handle, option_value, parameter))
            }
        } 
    }

    pub fn set_options(self: *CurlHandle, options: anytype) CurlError!void {
        const options_type = @TypeOf(options);
        const options_type_info = @typeInfo(options_type);
        if(options_type_info != .Struct) {
            @compileError("expected tuple or struct argument, found " ++ @typeName(options_type));
        }

        inline for (options) |opt| {
            try self.set_opt(opt[0], opt[1]);
        }
    }

    pub fn cleanup(self: *CurlHandle) void {
        c.curl_easy_cleanup(self.curl_handle);
    }
    
    pub fn send_request(self: *CurlHandle, alloc: std.mem.Allocator, request: *Request) !Response {
        try self.set_options(.{
            .{c.CURLOPT_VERBOSE, request.verbose_log},
            .{request.request_type, true},
            .{c.CURLOPT_URL, request.url},
            .{c.CURLOPT_USERAGENT, request.user_agent},
            .{c.CURLOPT_MAXREDIRS, request.max_redirs},
            .{c.CURLOPT_NOPROGRESS, !request.show_progress},
        });

        //TODO: What to do with post(upload) requests?
        switch(request.request_type) {
            .Post, .Upload => |data| {
                try self.set_options(.{
                    .{c.CURLOPT_POSTFIELDSIZE, data.len},
                    .{c.CURLOPT_POSTFIELDS, data.ptr}
                });
            },
            .Get => {}
        } 

        try request.ssl.set_options(self);
        const accept_type_string = try std.fmt.allocPrintZ(alloc, "Accpet: {s}", .{request.content_type}); 
        const contet_type_string = try std.fmt.allocPrintZ(alloc, "Content-Type: {s}", .{request.content_type}); 

        request.header_list = c.curl_slist_append(request.header_list, accept_type_string.ptr);
        request.header_list = c.curl_slist_append(request.header_list, contet_type_string.ptr);

        if (request.header_list == null) {
            //std.debug.print("Header list broken\n", .{});
        }

        var response_buffer = std.ArrayList(u8).init(alloc);

        try self.set_options(.{
            .{c.CURLOPT_HTTPHEADER, request.header_list},
            .{c.CURLOPT_WRITEFUNCTION, write_to_array_list_callback},
            .{c.CURLOPT_WRITEDATA, &response_buffer},
        });

        try tryCurl(c.curl_easy_perform(self.curl_handle));

        c.curl_slist_free_all(request.header_list);
        request.header_list = null;

        const response = try Response.from_curl(self, response_buffer);

        return response;
    }
};


