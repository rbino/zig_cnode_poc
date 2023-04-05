const std = @import("std");
const erl_interface = @import("erl_interface.zig");
const CNode = erl_interface.CNode;
const c = erl_interface.c;

pub fn main() !void {
    // Initialize erl_interface
    try erl_interface.init();

    const node_name = "zig_node";
    const cookie = null; // This can also be a string

    // Initialize the node
    var c_node = try CNode.init(node_name, cookie, 1);
    std.debug.print("Node {s} initialized with cookie {}\n", .{ node_name, cookie });

    // Start listening
    var server = try c_node.listen(100);
    defer server.close();
    std.debug.print("Listening on port {}\n", .{server.port});

    // Publish the server to epmd so other nodes can easily find it
    try server.publish();
    defer server.unpublish();
    std.debug.print("Registered to epmd\n", .{});

    // Accept a connection from another node
    const connection = try server.accept();
    defer connection.close();
    std.debug.print("Accepted connection\n", .{});

    const global_name = "ziggy";

    try connection.register(global_name, c_node.self_pid());
    std.debug.print("Registered pid in global registry as {s}\n", .{global_name});

    var msg: c.erlang_msg = undefined;
    var buf: c.ei_x_buff = undefined;

    while (true) {
        // TODO: wrap all the encoding/decoding stuff with Zig
        if (c.ei_x_new_with_version(&buf) != 0) unreachable;
        defer _ = c.ei_x_free(&buf);

        const rcv = c.ei_xreceive_msg(connection.fd, &msg, &buf);
        switch (rcv) {
            // Tick from the other node, ignore
            c.ERL_TICK => {
                std.debug.print("Received tick\n", .{});
                continue;
            },
            c.ERL_ERROR => return error.ReceiveError,
            else => {},
        }

        switch (msg.msgtype) {
            c.ERL_SEND => {
                std.debug.print("Received message\n", .{});

                var idx: c_int = 0;

                var version: c_int = undefined;
                if (c.ei_decode_version(buf.buff, &idx, &version) != 0) unreachable;
                std.debug.print("Version: {}\n", .{version});

                var arity: c_int = undefined;
                if (c.ei_decode_tuple_header(buf.buff, &idx, &arity) != 0) {
                    std.debug.print("Unexpected message, expecting a 2-element tuple\n", .{});
                    continue;
                }

                var sender: c.erlang_pid = undefined;
                if (c.ei_decode_pid(buf.buff, &idx, &sender) != 0) {
                    std.debug.print("Unexpected message, expecting a pid as first element\n", .{});
                    continue;
                }

                var atom_buf: [c.MAXATOMLEN:0]u8 = undefined;
                if (c.ei_decode_atom(buf.buff, &idx, &atom_buf) != 0) {
                    std.debug.print("Unexpected message, expecting an atom as second element\n", .{});
                    continue;
                }
                const atom = std.mem.sliceTo(&atom_buf, 0);
                std.debug.print("Received atom: {s}\n", .{atom});

                if (std.mem.eql(u8, atom, "ping")) {
                    var send_buf: c.ei_x_buff = undefined;
                    if (c.ei_x_new_with_version(&send_buf) != 0) unreachable;
                    if (c.ei_x_encode_atom(&send_buf, "pong") != 0) {
                        return error.EncodingError;
                    }
                    // TODO: why we need to explicitly send a pid and passing &msg.from doesn't work?
                    if (c.ei_send(connection.fd, &sender, send_buf.buff, send_buf.index) != 0) {
                        return error.SendError;
                    }
                }
            },
            c.ERL_REG_SEND => @panic("TODO"),
            c.ERL_LINK => @panic("TODO"),
            c.ERL_UNLINK => @panic("TODO"),
            c.ERL_EXIT => @panic("TODO"),
            else => unreachable,
        }
    }
}
