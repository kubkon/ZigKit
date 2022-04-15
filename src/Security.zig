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

pub const CMSDecoder = opaque {
    pub fn create() !*CMSDecoder {
        var decoder: *CMSDecoder = undefined;
        if (CMSDecoderCreate(&decoder) != 0) {
            return error.Failed;
        }
        return decoder;
    }

    pub fn release(self: *CMSDecoder) void {
        CFRelease(self);
    }

    pub fn updateMessage(self: *CMSDecoder, msg: []const u8) !void {
        const res = CMSDecoderUpdateMessage(self, msg.ptr, msg.len);
        if (res != 0) {
            return error.Failed;
        }
    }

    pub fn setDetachedContent(self: *CMSDecoder, bytes: []const u8) !void {
        const dref = CFData.create(bytes);
        defer dref.release();

        if (CMSDecoderSetDetachedContent(self, dref) != 0) {
            return error.Failed;
        }
    }

    pub fn finalizeMessage(self: *CMSDecoder) !void {
        if (CMSDecoderFinalizeMessage(self) != 0) {
            return error.Failed;
        }
    }

    pub fn getNumSigners(self: *CMSDecoder) !usize {
        var out: usize = undefined;
        if (CMSDecoderGetNumSigners(self, &out) != 0) {
            return error.Failed;
        }
        return out;
    }

    pub fn signerEmailAddress(self: *CMSDecoder, allocator: Allocator, index: usize) ![]const u8 {
        var ref: ?*CFString = null;
        if (ref) |r| r.release();
        const res = CMSDecoderCopySignerEmailAddress(self, index, &ref);
        if (res != 0) {
            return error.Failed;
        }
        return ref.?.cstr(allocator);
    }

    pub fn copyDetachedContent(self: *CMSDecoder) !?*CFData {
        var out: ?*CFData = null;
        const res = CMSDecoderCopyDetachedContent(self, &out);
        if (res != 0) {
            return error.Failed;
        }
        return out;
    }

    pub fn copyContent(self: *CMSDecoder) !?*CFData {
        var out: ?*CFData = null;
        const res = CMSDecoderCopyContent(self, &out);
        if (res != 0) {
            return error.Failed;
        }
        return out;
    }

    pub fn getSignerStatus(self: *CMSDecoder, index: usize) !CMSSignerStatus {
        const policy = SecPolicy.createiPhoneProfileApplicationSigning();
        defer policy.release();

        var status: CMSSignerStatus = undefined;
        if (CMSDecoderCopySignerStatus(self, index, policy, false, &status, null, null) != 0) {
            return error.Failed;
        }
        return status;
    }

    extern "c" fn CMSDecoderCreate(**CMSDecoder) c_int;
    extern "c" fn CMSDecoderSetDetachedContent(decoder: *CMSDecoder, detached_content: *CFData) c_int;
    extern "c" fn CMSDecoderUpdateMessage(
        decoder: *CMSDecoder,
        msg_bytes: *const anyopaque,
        msg_len: usize,
    ) c_int;
    extern "c" fn CMSDecoderFinalizeMessage(decoder: *CMSDecoder) c_int;
    extern "c" fn CMSDecoderGetNumSigners(decoder: *CMSDecoder, out: *usize) c_int;
    extern "c" fn CMSDecoderCopyDetachedContent(decoder: *CMSDecoder, out: *?*CFData) c_int;
    extern "c" fn CMSDecoderCopyContent(decoder: *CMSDecoder, out: *?*CFData) c_int;
    extern "c" fn CMSDecoderCopySignerEmailAddress(
        decoder: *CMSDecoder,
        index: usize,
        out: *?*CFString,
    ) c_int;
    extern "c" fn CMSDecoderCopySignerStatus(
        decoder: *CMSDecoder,
        index: usize,
        policy_or_array: *const anyopaque,
        eval_sec_trust: bool,
        out_status: *CMSSignerStatus,
        out_trust: ?*anyopaque,
        out_cert_verify_code: ?*c_int,
    ) c_int;
};

pub const SecPolicy = opaque {
    pub fn createiPhoneApplicationSigning() *SecPolicy {
        return SecPolicyCreateiPhoneApplicationSigning();
    }

    pub fn createiPhoneProfileApplicationSigning() *SecPolicy {
        return SecPolicyCreateiPhoneProfileApplicationSigning();
    }

    pub fn createMacOSProfileApplicationSigning() *SecPolicy {
        return SecPolicyCreateMacOSProfileApplicationSigning();
    }

    pub fn release(self: *SecPolicy) void {
        CFRelease(self);
    }

    extern "c" fn SecPolicyCreateiPhoneApplicationSigning() *SecPolicy;
    extern "c" fn SecPolicyCreateiPhoneProfileApplicationSigning() *SecPolicy;
    extern "c" fn SecPolicyCreateMacOSProfileApplicationSigning() *SecPolicy;
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

    pub fn release(self: *SecIdentity) void {
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

pub const CMSSignerStatus = enum(u32) {
    unsigned = 0,
    valid,
    needs_detached_content,
    invalid_signature,
    invalid_cert,
    invalid_index,
};

test {
    _ = testing.refAllDecls(@This());
    _ = testing.refAllDecls(CMSEncoder);
    _ = testing.refAllDecls(CMSDecoder);
    _ = testing.refAllDecls(SecCertificate);
    _ = testing.refAllDecls(SecIdentity);
    _ = testing.refAllDecls(SecPolicy);
}
