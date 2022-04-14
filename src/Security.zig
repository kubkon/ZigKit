const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const Allocator = mem.Allocator;
const CoreFoundation = @import("CoreFoundation.zig");
const CFData = CoreFoundation.CFData;
const CFRelease = CoreFoundation.CFRelease;
const CFString = CoreFoundation.CFString;

/// Wraps CMSEncoderRef type.
pub const CMSEncoder = opaque {
    pub fn create() !*CMSEncoder {
        var encoder: *CMSEncoder = undefined;
        if (CMSEncoderCreate(&encoder) != 0) {
            return error.Failed;
        }
        return encoder;
    }

    pub fn release(self: *CMSEncoder) void {
        CFRelease(self);
    }

    pub fn addSigner(self: *CMSEncoder, signer: *SecIdentity) !void {
        if (CMSEncoderAddSigners(self, signer) != 0) {
            return error.Failed;
        }
    }

    pub fn setSignerAlgorithm(self: *CMSEncoder, alg: SignerAlgorithm) !void {
        const res = switch (alg) {
            .sha256 => CMSEncoderSetSignerAlgorithm(self, kCMSEncoderDigestAlgorithmSHA256),
        };
        if (res != 0) {
            return error.Failed;
        }
    }

    pub fn setCertificateChainMode(self: *CMSEncoder, mode: CertificateChainMode) !void {
        if (CMSEncoderSetCertificateChainMode(self, mode) != 0) {
            return error.Failed;
        }
    }

    pub fn setHasDetachedContent(self: *CMSEncoder, value: bool) !void {
        if (CMSEncoderSetHasDetachedContent(self, value) != 0) {
            return error.Failed;
        }
    }

    pub fn updateContent(self: *CMSEncoder, content: []const u8) !void {
        if (CMSEncoderUpdateContent(self, content.ptr, content.len) != 0) {
            return error.Failed;
        }
    }

    pub fn finalize(self: *CMSEncoder) !*CFData {
        var out: *CFData = undefined;
        if (CMSEncoderCopyEncodedContent(self, &out) != 0) {
            return error.Failed;
        }
        return out;
    }

    extern "c" var kCMSEncoderDigestAlgorithmSHA256: *CFString;

    extern "c" fn CMSEncoderCreate(**CMSEncoder) c_int;
    extern "c" fn CMSEncoderAddSigners(encoder: *CMSEncoder, signer_or_array: *anyopaque) c_int;
    extern "c" fn CMSEncoderSetSignerAlgorithm(encoder: *CMSEncoder, digest_alg: *CFString) c_int;
    extern "c" fn CMSEncoderSetCertificateChainMode(encoder: *CMSEncoder, chain_mode: CertificateChainMode) c_int;
    extern "c" fn CMSEncoderSetHasDetachedContent(encoder: *CMSEncoder, detached_content: bool) c_int;
    extern "c" fn CMSEncoderUpdateContent(encoder: *CMSEncoder, content: *const anyopaque, len: usize) c_int;
    extern "c" fn CMSEncoderCopyEncodedContent(encoder: *CMSEncoder, out: **CFData) c_int;
};

pub const SecCertificate = opaque {
    pub fn initWithData(bytes: []const u8) !*SecCertificate {
        const data = CFData.create(bytes);
        defer data.release();

        if (SecCertificateCreateWithData(null, data)) |cert| {
            return cert;
        } else return error.InvalidX509Certificate;
    }

    pub fn release(self: *SecCertificate) void {
        CFRelease(self);
    }

    extern "c" fn SecCertificateCreateWithData(allocator: ?*anyopaque, data: *CFData) ?*SecCertificate;
};

pub const SecIdentity = opaque {
    pub fn initWithCertificate(cert: *SecCertificate) !*SecIdentity {
        var ident: *SecIdentity = undefined;
        if (SecIdentityCreateWithCertificate(null, cert, &ident) != 0) {
            return error.Failed;
        }
        return ident;
    }

    pub fn deinit(self: *SecIdentity) void {
        CFRelease(self);
    }

    extern "c" fn SecIdentityCreateWithCertificate(
        keychain_or_array: ?*anyopaque,
        cert: *SecCertificate,
        ident: **SecIdentity,
    ) c_int;
};

pub const SignerAlgorithm = enum {
    sha256,
};

pub const CertificateChainMode = enum(u32) {
    none = 0,
    signer_only,
    chain,
    chain_with_root,
    chain_with_root_or_fail,
};

test {
    _ = testing.refAllDecls(@This());
    _ = testing.refAllDecls(CMSEncoder);
    _ = testing.refAllDecls(SecCertificate);
    _ = testing.refAllDecls(SecIdentity);
}
