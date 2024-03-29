const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const CoreFoundation = @import("../CoreFoundation.zig");
const CFArray = CoreFoundation.CFArray;
const CFDictionary = CoreFoundation.CFDictionary;
const CFString = CoreFoundation.CFString;
const CFUrl = CoreFoundation.CFUrl;

pub const ADNCI_MSG = enum(u8) {
    CONNECTED = 1,
    DISCONNECTED = 2,
    UNKNOWN = 3,
    _,
};

pub const AMDeviceNotificationCallbackInfo = extern struct {
    device: *AMDevice,
    msg: u32,
};

pub const AMDevice = extern struct {
    _0: [16]u8,
    device_id: u32,
    product_id: u32,
    serial: [4]u8,
    _1: u32,
    _2: [4]u8,
    lockdown_conn: u32,
    _3: [8]u8,

    pub fn release(self: *AMDevice) void {
        AMDeviceRelease(self);
    }

    pub fn connect(self: *AMDevice) !void {
        if (AMDeviceConnect(self) != 0) {
            return error.Failed;
        }
    }

    pub fn disconnect(self: *AMDevice) !void {
        if (AMDeviceDisconnect(self) != 0) {
            return error.Failed;
        }
    }

    pub fn isPaired(self: *AMDevice) bool {
        return AMDeviceIsPaired(self) == 1;
    }

    pub fn getName(self: *AMDevice, allocator: Allocator) error{OutOfMemory}![]const u8 {
        const key = CFString.createWithBytes("DeviceName");
        defer key.release();
        const cfstr = AMDeviceCopyValue(self, null, key);
        defer cfstr.release();
        return cfstr.cstr(allocator);
    }

    pub fn getInterfaceType(self: *AMDevice) IntefaceType {
        return @as(IntefaceType, @enumFromInt(AMDeviceGetInterfaceType(self)));
    }

    pub fn secureTransferPath(self: *AMDevice, url: *CFUrl, opts: *CFDictionary, cb: Callback) !void {
        if (AMDeviceSecureTransferPath(0, self, url, opts, cb, 0) != 0) {
            return error.Failed;
        }
    }

    pub fn secureInstallApplication(self: *AMDevice, url: *CFUrl, opts: *CFDictionary, cb: Callback) !void {
        if (AMDeviceSecureInstallApplication(0, self, url, opts, cb, 0) != 0) {
            return error.Failed;
        }
    }

    pub fn validatePairing(self: *AMDevice) !void {
        if (AMDeviceValidatePairing(self) != 0) {
            return error.Failed;
        }
    }

    pub fn startSession(self: *AMDevice) !void {
        if (AMDeviceStartSession(self) != 0) {
            return error.Failed;
        }
    }

    pub fn stopSession(self: *AMDevice) !void {
        if (AMDeviceStopSession(self) != 0) {
            return error.Failed;
        }
    }

    pub fn installBundle(
        self: *AMDevice,
        bundle_path: []const u8,
        transfer_cb: Callback,
        install_cb: Callback,
    ) !void {
        const rel_url = CFUrl.createWithPath(bundle_path, false);
        defer rel_url.release();
        const url = rel_url.copyAbsoluteUrl();
        defer url.release();

        const keys = &[_]*CFString{CFString.createWithBytes("PackageType")};
        const values = &[_]*CFString{CFString.createWithBytes("Developer")};
        const opts = try CFDictionary.create(CFString, CFString, keys, values);
        defer {
            for (keys) |key| {
                key.release();
            }
            for (values) |value| {
                value.release();
            }
            opts.release();
        }

        try self.secureTransferPath(url, opts, transfer_cb);

        try self.connect();
        defer self.disconnect() catch {};

        assert(self.isPaired());
        try self.validatePairing();

        try self.startSession();
        defer self.stopSession() catch {};

        try self.secureInstallApplication(url, opts, install_cb);
    }

    /// Caller owns the returned memory.
    pub fn copyDeviceAppUrl(self: *AMDevice, allocator: Allocator, bundle_id: []const u8) !?[]const u8 {
        try self.connect();
        defer self.disconnect() catch {};

        assert(self.isPaired());
        try self.validatePairing();

        try self.startSession();
        defer self.stopSession() catch {};

        var maybe_out: ?*CFDictionary = undefined;
        defer if (maybe_out) |out| out.release();

        const value_obj = try CFArray.create(CFString, &[_]*CFString{
            CFString.createWithBytes("CFBundleIdentifier"),
            CFString.createWithBytes("Path"),
        });
        defer value_obj.release();

        const values = &[_]*CFArray{value_obj};
        const keys = &[_]*CFString{CFString.createWithBytes("ReturnAttributes")};
        const opts = try CFDictionary.create(CFString, CFArray, keys, values);
        defer opts.release();

        if (AMDeviceLookupApplications(self, opts, &maybe_out) != 0) {
            return error.Failed;
        }
        const out = maybe_out orelse return error.Failed;

        const bid = CFString.createWithBytes(bundle_id);
        defer bid.release();
        const raw_app_info = out.getValue(CFString, CFDictionary, bid) orelse return null;
        const app_dict = @as(*CFDictionary, @ptrCast(raw_app_info));
        const raw_path = app_dict.getValue(CFString, CFString, CFString.createWithBytes("Path")).?;
        const path = @as(*CFString, @ptrCast(raw_path));
        const url = CFUrl.CFURLCreateWithFileSystemPath(null, path, .posix, true);
        defer url.release();
        return try url.copyPath(allocator);
    }

    pub const Callback = fn (*CFDictionary, c_int) callconv(.C) c_int;

    extern "c" fn AMDeviceRelease(device: *AMDevice) void;
    extern "c" fn AMDeviceConnect(device: *AMDevice) c_int;
    extern "c" fn AMDeviceDisconnect(device: *AMDevice) c_int;
    extern "c" fn AMDeviceIsPaired(device: *AMDevice) c_int;
    extern "c" fn AMDeviceValidatePairing(device: *AMDevice) c_int;
    extern "c" fn AMDeviceStartSession(device: *AMDevice) c_int;
    extern "c" fn AMDeviceStopSession(device: *AMDevice) c_int;
    extern "c" fn AMDeviceCopyValue(device: *AMDevice, ?*anyopaque, key: *CFString) *CFString;
    extern "c" fn AMDeviceGetInterfaceType(device: *AMDevice) c_int;
    extern "c" fn AMDeviceSecureTransferPath(
        c_int,
        device: *AMDevice,
        url: *CFUrl,
        opts: *CFDictionary,
        cb: Callback,
        cbarg: c_int,
    ) c_int;
    extern "c" fn AMDeviceSecureInstallApplication(
        c_int,
        device: *AMDevice,
        url: *CFUrl,
        opts: *CFDictionary,
        cb: Callback,
        cbarg: c_int,
    ) c_int;
    extern "c" fn AMDeviceLookupApplications(
        device: *AMDevice,
        opts: *CFDictionary,
        out: *?*CFDictionary,
    ) c_int;
};

pub const IntefaceType = enum(isize) {
    usb = 1,
    wifi,
    companion,
    _,
};

pub const AMDeviceNotification = extern struct {
    _0: u32,
    _1: u32,
    _2: u32,
    callback: AMDeviceNotificationCallback,
    _3: u32,
};

pub const AMDeviceNotificationCallback = fn (
    *AMDeviceNotificationCallbackInfo,
    ?*anyopaque,
) callconv(.C) void;

pub fn subscribe(cb: AMDeviceNotificationCallback, opts: *CFDictionary) !*AMDeviceNotification {
    var notify: *AMDeviceNotification = undefined;
    if (AMDeviceNotificationSubscribeWithOptions(cb, 0, 0, null, &notify, opts) != 0) {
        return error.Failed;
    }
    return notify;
}

extern "c" fn AMDeviceNotificationSubscribeWithOptions(
    callback: AMDeviceNotificationCallback,
    u32,
    u32,
    ?*anyopaque,
    notification: **AMDeviceNotification,
    options: ?*CFDictionary,
) c_int;
