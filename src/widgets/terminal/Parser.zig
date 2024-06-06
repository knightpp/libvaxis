//! An ANSI VT Parser
const Parser = @This();

const std = @import("std");
const Reader = std.io.AnyReader;

/// A terminal event
const Event = union(enum) {
    print: []const u8,
    c0: u8,
    escape: []const u8,
    ss2: u8,
    ss3: u8,
    csi: []const u8,
    osc: []const u8,
    apc: []const u8,
};

buf: std.ArrayList(u8),
/// a leftover byte from a ground event
pending_byte: ?u8 = null,

pub fn parseReader(self: *Parser, reader: Reader) !Event {
    self.buf.clearRetainingCapacity();
    while (true) {
        const b = if (self.pending_byte) |p| p else try reader.readByte();
        self.pending_byte = null;
        switch (b) {
            // Escape sequence
            0x1b => {
                const next = try reader.readByte();
                switch (next) {
                    0x4E => return .{ .ss2 = try reader.readByte() },
                    0x4F => return .{ .ss3 = try reader.readByte() },
                    0x50 => try skipUntilST(reader), // DCS
                    0x58 => try skipUntilST(reader), // SOS
                    0x5B => return self.parseCsi(reader), // CSI
                    0x5D => return self.parseOsc(reader), // OSC
                    0x5E => try skipUntilST(reader), // PM
                    0x5F => return self.parseApc(reader), // APC

                    0x20...0x2F => {
                        try self.buf.append(next);
                        return self.parseEscape(reader); // ESC
                    },
                    else => {
                        try self.buf.append(next);
                        return .{ .escape = self.buf.items };
                    },
                }
            },
            // C0 control
            0x00...0x1a,
            0x1c...0x1f,
            => return .{ .c0 = b },
            else => {
                try self.buf.append(b);
                return self.parseGround(reader);
            },
        }
    }
}

inline fn parseGround(self: *Parser, reader: Reader) !Event {
    while (true) {
        const b = try reader.readByte();
        switch (b) {
            0x00...0x1f => {
                self.pending_byte = b;
                return .{ .print = self.buf.items };
            },
            else => try self.buf.append(b),
        }
    }
}

/// parse until b >= 0x30
inline fn parseEscape(self: *Parser, reader: Reader) !Event {
    while (true) {
        const b = try reader.readByte();
        switch (b) {
            0x20...0x2F => continue,
            else => return .{ .escape = self.buf.items },
        }
    }
}

inline fn parseApc(self: *Parser, reader: Reader) !Event {
    while (true) {
        const b = try reader.readByte();
        switch (b) {
            0x00...0x17,
            0x19,
            0x1c...0x1f,
            => continue,
            0x1b => {
                try reader.skipBytes(1, .{ .buf_size = 1 });
                return .{ .apc = self.buf.items };
            },
            else => try self.buf.append(b),
        }
    }
}

/// Skips sequences until we see an ST (String Terminator, ESC \)
inline fn skipUntilST(reader: Reader) !void {
    try reader.skipUntilDelimiterOrEof('\x1b');
    try reader.skipBytes(1, .{ .buf_size = 1 });
}

/// Parses an OSC sequence
inline fn parseOsc(self: *Parser, reader: Reader) !Event {
    while (true) {
        const b = try reader.readByte();
        switch (b) {
            0x00...0x06,
            0x08...0x17,
            0x19,
            0x1c...0x1f,
            => continue,
            0x1b => {
                try reader.skipBytes(1, .{ .buf_size = 1 });
                return .{ .osc = self.buf.items };
            },
            0x07 => return .{ .osc = self.buf.items },
            else => try self.buf.append(b),
        }
    }
}

inline fn parseCsi(self: *Parser, reader: Reader) !Event {
    while (true) {
        const b = try reader.readByte();
        try self.buf.append(b);
        switch (b) {
            // Really we should execute C0 controls, but we just ignore them
            0x40...0xFF => return .{ .csi = self.buf.items },
            else => continue,
        }
    }
}
