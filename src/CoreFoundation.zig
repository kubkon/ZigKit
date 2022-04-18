const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const mem = std.mem;
const testing = std.testing;

const Allocator = mem.Allocator;

// A workaround until stage 2 is shipped
fn getFunctionPointer(comptime function_type: type) type {
    return switch (builtin.zig_backend) {
        .stage1 => function_type,
        else => *const function_type,
    };
}

// Basic types
pub const CFIndex = c_long;
pub const CFOptionFlags = c_long;
pub const CFTypeID = c_ulong;
pub const CFTimeInterval = f64; // c_double
pub const CFAbsoluteTime = CFTimeInterval;
pub const Boolean = bool;
pub const CFComparisonResult = enum(CFIndex) {
    kCFCompareLessThan = -1,
    kCFCompareEqualTo = 0,
    kCFCompareGreaterThan = 1,
};

pub const CFRange = extern struct {
    location: CFIndex,
    length: CFIndex,
};

pub const CFComparatorFunction = fn (*const anyopaque, *const anyopaque, *anyopaque) callconv(.C) CFComparisonResult;

// A struct to help manage how the allocator callbacks wrap a zig allocator.
// Also used as the underlying type pointed to by the context struct we initialise
// to wrap zig allocators using CFAllocator.
// Because zig allocators work with slices - we have to allocate a little bit of
// extra memory than we normally would to recreate slice lengths.
const ZigAllocatorCallbacks = struct {
    pub fn allocateCallback(alloc_size: CFIndex, hint: CFOptionFlags, opaque_info: ?*anyopaque) callconv(.C) ?*anyopaque {
        _ = hint; // hint is always unused
        const allocator = opaqueInfoToAllocator(opaque_info);
        const actual_alloc_size = @sizeOf(usize) + @intCast(usize, alloc_size);
        const bytes = allocator.alignedAlloc(u8, @alignOf(usize), actual_alloc_size) catch {
            return null;
        };
        return rootSliceToData(bytes);
    }

    pub fn deallocateCallback(data: *anyopaque, opaque_info: ?*anyopaque) callconv(.C) void {
        const allocator = opaqueInfoToAllocator(opaque_info);
        allocator.free(dataToRootSlice(data));
    }

    pub fn reallocateCallback(old_data: *anyopaque, new_size: CFIndex, hint: CFOptionFlags, opaque_info: ?*anyopaque) callconv(.C) ?*anyopaque {
        _ = hint; // hint is always unused
        const allocator = opaqueInfoToAllocator(opaque_info);
        const actual_new_size = @sizeOf(usize) + @intCast(usize, new_size);
        const new_data = allocator.realloc(dataToRootSlice(old_data), actual_new_size) catch {
            return null;
        };
        return rootSliceToData(new_data);
    }

    fn opaqueInfoToAllocator(opaque_info: ?*anyopaque) *const Allocator {
        return @ptrCast(*const Allocator, @alignCast(@alignOf(Allocator), opaque_info.?));
    }

    fn dataToRootSlice(data: *anyopaque) []u8 {
        const data_root = @ptrCast([*]u8, data) - @sizeOf(usize);
        const length = mem.bytesToValue(usize, data_root[0..@sizeOf(usize)]);
        return data_root[0..length];
    }

    fn rootSliceToData(root_slice: []u8) *anyopaque {
        mem.bytesAsValue(usize, root_slice[0..@sizeOf(usize)]).* = root_slice.len;
        return @ptrCast(*anyopaque, root_slice[@sizeOf(usize)..]);
    }
};

/// Wraps the CFAllocatorRef type.
pub const CFAllocator = opaque {

    /// Construct a CFAllocator from a zig allocator, the second allocator argument can optionally be
    /// if you want to allocator the data used to manager the allocator itself using a different
    /// allocator.
    ///
    /// It is recommended that you construct a CFAllocator from a zig allocator once up-front & re-use it
    /// as allocations are needed to construct an allocator...
    ///
    /// The allocator pointed to must be valid for the lifetime of the CFAllocator.
    pub fn createFromZigAllocator(allocator: *const Allocator, allocator_allocator: ?*CFAllocator) !*CFAllocator {
        var allocator_context = CFAllocatorContext{
            .version = 0, // the ony valid value
            .info = @intToPtr(*anyopaque, @ptrToInt(allocator)),
            .allocate = ZigAllocatorCallbacks.allocateCallback,
            .deallocate = ZigAllocatorCallbacks.deallocateCallback,
            .reallocate = ZigAllocatorCallbacks.reallocateCallback,
            .preferredSize = null,
            .copyDescription = null,
            .retain = null,
            .release = null,
        };

        if (CFAllocatorCreate(allocator_allocator, &allocator_context)) |cf_allocator| {
            return cf_allocator;
        } else {
            return error.OutOfMemory;
        }
    }

    extern "C" const kCFAllocatorDefault: ?*CFAllocator;
    extern "C" const kCFAllocatorMalloc: *CFAllocator;
    extern "C" const kCFAllocatorMallocZone: *CFAllocator;
    extern "C" const kCFAllocatorSystemDefault: *CFAllocator;
    extern "C" const kCFAllocatorNull: *CFAllocator;
    extern "C" const kCFAllocatorUseContext: *CFAllocator;

    extern "c" fn CFAllocatorCreate(allocator: ?*CFAllocator, context: *CFAllocatorContext) ?*CFAllocator;

    extern "C" fn CFAllocatorAllocate(allocator: ?*CFAllocator, size: CFIndex, hint: CFOptionFlags) ?*anyopaque;
    extern "C" fn CFAllocatorDeallocate(allocator: ?*CFAllocator, ptr: *anyopaque) void;
    extern "C" fn CFAllocatorGetPreferredSizeForSize(allocator: ?*CFAllocator, size: CFIndex, hint: CFOptionFlags) CFIndex;
    extern "C" fn CFAllocatorReallocate(allocator: ?*CFAllocator, ptr: ?*anyopaque, newsize: CFIndex, hint: CFOptionFlags) ?*anyopaque;

    extern "C" fn CFAllocatorGetDefault() *CFAllocator;
    extern "C" fn CFAllocatorSetDefault(allocator: *CFAllocator) void;

    extern "c" fn CFAllocatorGetContext(allocator: ?*CFAllocator, out_context: *CFAllocatorContext) void;

    extern "C" fn CFAllocatorGetTypeID() CFTypeID;

    pub const CFAllocatorAllocateCallBack = fn (CFIndex, CFOptionFlags, ?*anyopaque) callconv(.C) ?*anyopaque;
    pub const CFAllocatorCopyDescriptionCallBack = fn (?*anyopaque) callconv(.C) *CFString;
    pub const CFAllocatorDeallocateCallback = fn (*anyopaque, ?*anyopaque) callconv(.C) void;
    pub const CFAllocatorPreferredSizeCallBack = fn (CFIndex, CFOptionFlags, ?*anyopaque) callconv(.C) CFIndex;
    pub const CFAllocatorReallocateCallBack = fn (*anyopaque, CFIndex, CFOptionFlags, ?*anyopaque) callconv(.C) ?*anyopaque;
    pub const CFAllocatorReleaseCallBack = fn (?*anyopaque) callconv(.C) *anyopaque;
    pub const CFAllocatorRetainCallBack = fn (?*anyopaque) callconv(.C) *anyopaque;

    /// Provides the layout of the CFAllocatorContext type.
    pub const CFAllocatorContext = extern struct {
        version: CFIndex,
        info: ?*anyopaque,
        retain: ?getFunctionPointer(CFAllocatorRetainCallBack),
        release: ?getFunctionPointer(CFAllocatorReleaseCallBack),
        copyDescription: ?getFunctionPointer(CFAllocatorCopyDescriptionCallBack),
        allocate: getFunctionPointer(CFAllocatorAllocateCallBack),
        reallocate: getFunctionPointer(CFAllocatorReallocateCallBack),
        deallocate: ?getFunctionPointer(CFAllocatorDeallocateCallback),
        preferredSize: ?getFunctionPointer(CFAllocatorPreferredSizeCallBack),
    };
};

/// Wraps the CFArrayRef type
pub const CFArray = opaque {
    // An alias to make opaque array value types a bit less confusing.
    pub const OpaqueArrayValueType = ?*const anyopaque;
    pub fn create(allocator: ?*CFAllocator, values: []const OpaqueArrayValueType, call_backs: ?*CFArrayCallBacks) !*CFArray {
        if (CFArrayCreate(allocator, values.ptr, @intCast(CFIndex, values.len), call_backs)) |cfarray| {
            return cfarray;
        } else {
            return error.OutOfMemory;
        }
    }

    extern "C" fn CFArrayCreate(allocator: ?*CFAllocator, values: [*]const OpaqueArrayValueType, num_values: CFIndex, call_backs: ?*CFArrayCallBacks) ?*CFArray;
    extern "C" fn CFArrayCreateCopy(allocator: ?*CFAllocator, the_array: *CFArray) ?*CFArray;

    extern "C" fn CFArrayBSearchValues(the_array: *CFArray, range: CFRange, value: OpaqueArrayValueType, comparator: ?getFunctionPointer(CFComparatorFunction), context: ?*anyopaque) CFIndex;
    extern "C" fn CFArrayContainsValue(the_array: *CFArray, range: CFRange, value: OpaqueArrayValueType) Boolean;
    extern "C" fn CFArrayGetCount(the_array: *CFArray) CFIndex;
    extern "C" fn CFArrayGetCountOfValue(the_array: *CFArray, range: CFRange, value: OpaqueArrayValueType) CFIndex;
    extern "C" fn CFArrayGetFirstIndexOfValue(the_array: *CFArray, range: CFRange, value: OpaqueArrayValueType) CFIndex;
    extern "C" fn CFArrayGetLastIndexOfValue(the_array: *CFArray, range: CFRange, value: OpaqueArrayValueType) CFIndex;
    extern "C" fn CFArrayGetValues(the_array: *CFArray, range: CFRange, values: [*]OpaqueArrayValueType) void;
    extern "C" fn CFArrayGetValueAtIndex(the_array: *CFArray, index: CFIndex) OpaqueArrayValueType;

    pub const CFArrayRetainCallBack = fn (*CFAllocator, OpaqueArrayValueType) callconv(.C) OpaqueArrayValueType;
    pub const CFArrayReleaseCallBack = fn (*CFAllocator, OpaqueArrayValueType) callconv(.C) void;
    pub const CFArrayCopyDescriptionCallBack = fn (OpaqueArrayValueType) callconv(.C) *CFString;
    pub const CFArrayEqualCallBack = fn (OpaqueArrayValueType, OpaqueArrayValueType) callconv(.C) Boolean;

    pub const CFArrayCallBacks = extern struct {
        version: CFIndex,
        retain: ?getFunctionPointer(CFArrayRetainCallBack),
        release: ?getFunctionPointer(CFArrayReleaseCallBack),
        copy_description: ?getFunctionPointer(CFArrayCopyDescriptionCallBack),
        equal: ?getFunctionPointer(CFArrayEqualCallBack),
    };
};

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

/// Wraps CFDateRef type.
pub const CFDate = opaque {
    extern "C" fn CFDateCompare(the_date: *CFDate, other_date: *CFDate, context: ?*anyopaque) CFComparisonResult;
    extern "C" fn CFDateCreate(allocator: ?*CFAllocator, at: CFAbsoluteTime) ?*CFDate;
    extern "C" fn CFDateGetAbsoluteTime(the_date: *CFDate) CFAbsoluteTime;
    extern "C" fn CFDateGetTimeIntervalSinceDate(the_date: *CFDate, other_date: *CFDate) CFTimeInterval;
    extern "C" fn CFDateGetTypeID() CFTypeID;
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

/// Wraps CFDictionaryRef type.
pub const CFDictionary = opaque {
    pub fn create(comptime Key: type, comptime Value: type, keys: []*Key, values: []*Value) *CFDictionary {
        assert(keys.len == values.len);
        return CFDictionaryCreate(
            null,
            @ptrCast([*]*const anyopaque, keys),
            @ptrCast([*]*const anyopaque, values),
            keys.len,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks,
        );
    }

    pub fn release(self: *CFDictionary) void {
        CFRelease(self);
    }

    pub fn getValue(self: *CFDictionary, comptime Key: type, comptime Value: type, key: *Key) ?*Value {
        const ptr = CFDictionaryGetValue(self, @ptrCast(*anyopaque, key)) orelse return null;
        return @ptrCast(*Value, ptr);
    }

    extern "c" fn CFDictionaryCreate(
        allocator: ?*anyopaque,
        keys: [*]*const anyopaque,
        values: [*]*const anyopaque,
        num_values: usize,
        key_cb: *const anyopaque,
        value_cb: *const anyopaque,
    ) *CFDictionary;
    extern "c" fn CFDictionaryGetValue(dict: *CFDictionary, key: *anyopaque) ?*anyopaque;

    extern "c" var kCFTypeDictionaryKeyCallBacks: anyopaque;
    extern "c" var kCFTypeDictionaryValueCallBacks: anyopaque;
};

/// Wraps CFBooleanRef type.
pub const CFBoolean = opaque {
    pub fn @"true"() *CFBoolean {
        return kCFBooleanTrue;
    }

    pub fn @"false"() *CFBoolean {
        return kCFBooleanFalse;
    }

    pub fn release(self: *CFBoolean) void {
        CFRelease(self);
    }

    extern "c" var kCFBooleanTrue: *CFBoolean;
    extern "c" var kCFBooleanFalse: *CFBoolean;
};

/// Wraps CFUrl type.
pub const CFUrl = opaque {
    pub fn createWithPath(path: []const u8, is_dir: bool) *CFUrl {
        const cpath = CFString.createWithBytes(path);
        defer cpath.release();
        return CFURLCreateWithFileSystemPath(null, cpath, .posix, is_dir);
    }

    pub fn copyAbsoluteUrl(self: *CFUrl) *CFUrl {
        return CFURLCopyAbsoluteURL(self);
    }

    pub fn copyPath(self: *CFUrl, allocator: Allocator) ![]const u8 {
        const cpath = CFURLCopyFileSystemPath(self, .posix);
        defer cpath.release();
        return cpath.cstr(allocator);
    }

    pub fn release(self: *CFUrl) void {
        CFRelease(self);
    }

    extern "c" fn CFURLCreateWithFileSystemPath(
        ?*anyopaque,
        path: *CFString,
        path_style: PathStyle,
        is_dir: bool,
    ) *CFUrl;
    extern "c" fn CFURLCopyAbsoluteURL(*CFUrl) *CFUrl;
    extern "c" fn CFURLCopyFileSystemPath(*CFUrl, PathStyle) *CFString;
};

pub const PathStyle = enum(usize) {
    posix = 0,
    hfs,
    windows,
};

pub const UTF8_ENCODING: u32 = 0x8000100;

pub extern "c" fn CFRelease(*anyopaque) void;

test {
    _ = testing.refAllDecls(@This());
    _ = testing.refAllDecls(ZigAllocatorCallbacks);
    _ = testing.refAllDecls(CFAllocator);
    _ = testing.refAllDecls(CFAllocator.CFAllocatorContext);
    _ = testing.refAllDecls(CFArray);
    _ = testing.refAllDecls(CFArray.CFArrayCallBacks);
    _ = testing.refAllDecls(CFData);
    _ = testing.refAllDecls(CFDate);
    _ = testing.refAllDecls(CFString);
    _ = testing.refAllDecls(CFDictionary);
    _ = testing.refAllDecls(CFBoolean);
    _ = testing.refAllDecls(CFUrl);
}
