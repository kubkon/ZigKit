const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const Allocator = mem.Allocator;

/// Wraps CFDataRef type.
pub const CFData = opaque {
    pub fn create(bytes: []const u8) *CFData {
        return CFDataCreate(null, bytes.ptr, bytes.len);
    }

    pub fn release(self: *CFData) void {
        CFRelease(self);
    }

    pub fn len(self: *CFData) usize {
        return @intCast(usize, CFDataGetLength(self));
    }

    pub fn asSlice(self: *CFData) []const u8 {
        const ptr = CFDataGetBytePtr(self);
        return @ptrCast([*]const u8, ptr)[0..self.len()];
    }

    extern "c" fn CFDataCreate(allocator: ?*anyopaque, bytes: [*]const u8, length: usize) *CFData;
    extern "c" fn CFDataGetBytePtr(*CFData) *const u8;
    extern "c" fn CFDataGetLength(*CFData) i32;
};

/// Wraps CFStringRef type.
pub const CFString = opaque {
    pub fn createWithBytes(bytes: []const u8) *CFString {
        return CFStringCreateWithBytes(null, bytes.ptr, bytes.len, UTF8_ENCODING, false);
    }

    pub fn release(self: *CFString) void {
        CFRelease(self);
    }

    /// Caller owns the memory.
    pub fn cstr(self: *CFString, allocator: Allocator) error{OutOfMemory}![]u8 {
        if (CFStringGetCStringPtr(self, UTF8_ENCODING)) |ptr| {
            const c_str = mem.sliceTo(@ptrCast([*:0]const u8, ptr), 0);
            return allocator.dupe(u8, c_str);
        }

        const buf_size = 1024;
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        try buf.resize(buf_size);

        while (!CFStringGetCString(self, buf.items.ptr, buf.items.len, UTF8_ENCODING)) {
            try buf.resize(buf.items.len + buf_size);
        }

        return buf.toOwnedSlice();
    }

    extern "c" fn CFStringCreateWithBytes(
        allocator: ?*anyopaque,
        bytes: [*]const u8,
        len: usize,
        encooding: u32,
        is_extern: bool,
    ) *CFString;
    extern "c" fn CFStringGetLength(str: *CFString) usize;
    extern "c" fn CFStringGetCStringPtr(str: *CFString, encoding: u32) ?*const u8;
    extern "c" fn CFStringGetCString(str: *CFString, buffer: [*]u8, size: usize, encoding: u32) bool;
};

pub const UTF8_ENCODING: u32 = 0x8000100;

pub extern "c" fn CFRelease(*anyopaque) void;

test {
    _ = testing.refAllDecls(@This());
    _ = testing.refAllDecls(CFData);
    _ = testing.refAllDecls(CFString);
}
