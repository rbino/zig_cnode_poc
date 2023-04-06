const std = @import("std");
const assert = std.debug.assert;
const c = @import("erl_interface.zig").c;
const Pid = @import("erl_interface.zig").Pid;

const TermTypeInternal = enum(c_int) {
    atom = c.ERL_ATOM_EXT,
    pid = c.ERL_PID_EXT,
    large_tuple = c.ERL_LARGE_TUPLE_EXT,
    small_tuple = c.ERL_SMALL_TUPLE_EXT,
    // TODO: add all the rest
};

pub const Atom = struct {
    pub const Encoding = enum {
        utf8,
        latin1,
    };

    name: []const u8,
    encoding: Encoding,
};

pub const TupleHeader = struct {
    arity: u32,
};

pub const TermType = enum {
    atom,
    pid,
    tuple_header,
    // TODO: add all the rest

    pub fn from_internal(internal: TermTypeInternal) TermType {
        return switch (internal) {
            .atom => .atom,
            .pid => .pid,
            .small_tuple, .large_tuple => .tuple_header,
        };
    }
};

pub const Term = union(enum) {
    atom: Atom,
    pid: Pid,
    tuple_header: TupleHeader,
    // TODO: all the rest

};

const TermStream = struct {
    buffer: []const u8,
    index: c_int = 0,

    pub fn init(self: *TermStream) !void {
        if (self.buffer.len < 1) return error.EndOfStream;

        var version: c_int = undefined;
        if (c.ei_decode_version(self.buffer.ptr, &self.index, &version) < 0)
            return error.InvalidVersionNumber;
    }

    pub fn peek_type(self: TermStream) !TermType {
        if (self.index >= self.buffer.len) return error.EndOfStream;

        var term_type_int: c_int = undefined;
        var term_size: c_int = undefined;

        // This can't fail
        if (c.ei_get_type(self.buffer.ptr, &self.index, &term_type_int, &term_size) < 0) unreachable;

        return TermType.from_internal(@intToEnum(TermTypeInternal, term_type_int));
    }

    /// Reads (consuming it) the next term in the stream. Returns null if no more terms are available.
    pub fn read_term(self: *TermStream) !?Term {
        const term_type = self.peek_type() catch |err| {
            if (err == .EndOfStream) {
                return null;
            } else {
                return err;
            }
        };

        return switch (term_type) {
            .atom => .{ .atom = try self.pop_atom() },
            .pid => .{ .pid = try self.pop_pid() },
            .tuple_header => .{ .tuple_header = try self.pop_tuple_header() },
        };
    }

    pub fn read_atom(self: *TermStream) !Atom {
        // The original ei_decode_atom copies the bytes, possibly converting the to/from utf8/latin1.
        // Here we just point to the slice to the existing atom string and return both the name and
        // the encoding to the caller.
        // This way we don't have to allocate and the caller can decide how to handle encoding.

        // Restrict the buffer to what we haven't consumed yet
        const buffer = self.buffer[@intCast(usize, self.index)..];

        // The tag whould correspond to the atom type.
        var name_start: usize = undefined;
        var length: usize = undefined;
        var encoding: Atom.Encoding = undefined;
        switch (buffer[0]) {
            c.ERL_SMALL_ATOM_EXT => {
                encoding = .latin1;
                length = buffer[1];
                name_start = 2;
            },
            c.ERL_ATOM_EXT => {
                encoding = .latin1;
                length = std.mem.readIntSliceBig(u16, buffer[1..]);
                name_start = 3;
            },
            c.ERL_SMALL_ATOM_UTF8_EXT => {
                encoding = .utf8;
                length = buffer[1];
                name_start = 2;
            },
            c.ERL_ATOM_UTF8_EXT => {
                encoding = .utf8;
                length = std.mem.readIntSliceBig(u16, buffer[1..]);
                name_start = 3;
            },
            else => return error.InvalidTerm,
        }

        const name_end = name_start + length;
        const name = buffer[name_start..name_end];

        // Bump the index
        self.index += @intCast(c_int, name_end);

        return .{ .name = name, .encoding = encoding };
    }

    pub fn read_tuple_header(self: *TermStream) !TupleHeader {
        const buffer = self.buffer;
        var arity: c_int = undefined;
        if (c.ei_decode_tuple_header(buffer.ptr, &self.index, &arity) < 0) return error.InvalidTerm;
        return .{ .arity = @intCast(u32, arity) };
    }

    pub fn read_pid(self: *TermStream) !Pid {
        const buffer = self.buffer;
        var pid: Pid = undefined;
        if (c.ei_decode_pid(buffer.ptr, &self.index, &pid) < 0) return error.InvalidTerm;
        return pid;
    }
};

pub fn stream(buffer: []const u8) TermStream {
    return .{
        .index = 0,
        .buffer = buffer,
    };
}
