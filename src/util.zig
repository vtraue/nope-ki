const std = @import("std");
const c = @import("sio_c.zig"); 
const thread = std.Thread;
const atomic = std.atomic;
const Ordering = std.builtin.AtomicOrder;

pub const RustString = struct {
    inner: c.RustString,

    pub fn new(initial_size: usize) RustString {
        var inner = c.rust_string_new(initial_size);
        return RustString {
            .inner = inner
        };
    }

    pub fn from_slice(slice: []const u8) RustString {
        var string = RustString.new(slice.len + 10);
        var buffer = string.as_mem_slice();
        std.mem.copy(u8, buffer, slice);
        string.inner.len = slice.len;

        return string;
    } 

    pub fn from_rust(string: c.RustString) RustString {
        return RustString {.inner = string};
    } 

    pub fn as_string_slice(self: *const RustString) []u8 {
        return @ptrCast([*]u8, self.inner.buf)[0..self.inner.len];
    }
    pub fn as_mem_slice(self: *const RustString) []u8 {
        return @ptrCast([*]u8, self.inner.buf)[0..self.inner.capacity];
    }
};

pub const ThreadQueueError = error {
    Full,
    Empty,
    Race
};

//NOTE: Right now, this is just going to be 1:1
pub fn ThreadQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: []T,
        next_read_pos: atomic.Atomic(u32),
        next_write_pos: atomic.Atomic(u32),
        len: atomic.Atomic(u32),
        event: std.Thread.ResetEvent,

        pub fn new(alloc: std.mem.Allocator, size: usize) !Self {
            var buffer = try alloc.alloc(T, size);

            return Self {
                .buffer = buffer,
                .next_read_pos = atomic.Atomic(u32).init(0),
                .next_write_pos = atomic.Atomic(u32).init(0),
                .len = atomic.Atomic(u32).init(0),
                .event = .{}
            };
        }
        
        pub fn push_back(self: *Self, value: T) ThreadQueueError!void {
            //TODO: SeqCst because i'm lazy. We could propably settle for something else.
            const old_next_write_pos = self.next_write_pos.load(Ordering.SeqCst);
            const new_write_pos = (old_next_write_pos + 1) % (@intCast(u32, self.buffer.len));
            const old_next_read_pos = self.next_read_pos.load(Ordering.SeqCst);

            if (new_write_pos == old_next_read_pos) {
                std.debug.print("The queue is full", .{});
                return ThreadQueueError.Full;
            }

            self.buffer[old_next_write_pos] = value;
            self.next_write_pos.store(new_write_pos, Ordering.SeqCst);

            _ = self.len.fetchAdd(1, Ordering.SeqCst);
            self.event.set();
       }

        pub fn get_index(self: *Self) ThreadQueueError!usize {

            const old_read_index = self.next_read_pos.load(Ordering.SeqCst);
            const old_write_position = self.next_write_pos.load(Ordering.SeqCst);
            const new_next_read_pos = (old_read_index + 1) % @intCast(u32,self.buffer.len);

            if (old_read_index != old_write_position) {
                //TODO: FIX THIS!!
                _ = self.next_read_pos.compareAndSwap(old_read_index, new_next_read_pos, Ordering.SeqCst, Ordering.SeqCst); 
                return old_read_index;
            }
            return ThreadQueueError.Empty; 
        }

        pub fn pop_raw(self: *Self, index: usize) T {
            const val = self.buffer[index];
            const old_len = self.len.fetchSub(1, Ordering.SeqCst);
            const new_len = old_len - 1;

            if(new_len == 0) {
                self.event.reset();

            }
            return val;
        }

        pub fn try_pop_front(self: *Self) ?T {
            while(true) {
                const index = self.get_index();
                if(index) |num| {
                    return self.pop_raw(num);
                } else |err| {
                    switch(err) {
                        error.Race => continue,
                        else => return null
                    }
                }
            }
        }
        
        pub fn block_pop_front(self: *Self) T {
            while(true) {
                const index = self.get_index();
                if(index) |num| {
                    return self.pop_raw(num);
                }
                else |err| {
                    switch (err) {
                       error.Empty => {
                           self.event.wait(); 
                           continue;
                       },
                       else => continue
                    }
                }
            }
        }
    };
}


