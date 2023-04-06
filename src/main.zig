const std = @import("std");
const erl_interface = @import("erl_interface.zig");
const CNode = erl_interface.CNode;
const Connection = erl_interface.Connection;
const c = erl_interface.c;
const external_term_format = @import("external_term_format.zig");

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
        if (c.ei_x_new_with_version(&buf) != 0) unreachable;
        defer _ = c.ei_x_free(&buf);

        const rcv = c.ei_xreceive_msg(connection.fd, &msg, &buf);
        switch (rcv) {
            c.ERL_MSG => {
                try handle_message(connection, &msg, &buf);
            },
            // Tick from the other node, ignore
            c.ERL_TICK => {
                std.debug.print("Received tick\n", .{});
                continue;
            },
            c.ERL_ERROR => {
                return error.ReceiveError;
            },
            else => unreachable,
        }
    }
}

fn handle_message(connection: Connection, msg: *const c.erlang_msg, buf: *const c.ei_x_buff) !void {
    switch (msg.msgtype) {
        c.ERL_SEND => {
            std.debug.print("Received message\n", .{});

            const buffer = buf.buff[0..@intCast(usize, buf.index)];
            var stream = external_term_format.stream(buffer);
            try stream.init();

            // Expect a message in the format {pid(), atom()}, and reply :pong if the atom is :ping
            const tuple_header = stream.read_tuple_header() catch {
                std.debug.print("Unexpected message, expecting a tuple\n", .{});
                return;
            };
            if (tuple_header.arity != 2) {
                std.debug.print("Unexpected message, expecting a 2-elem tuple\n", .{});
                return;
            }

            const sender = stream.read_pid() catch {
                std.debug.print("Unexpected message, expecting a pid as first element\n", .{});
                return;
            };

            const atom = stream.read_atom() catch {
                std.debug.print("Unexpected message, expecting an atom as second element\n", .{});
                return;
            };

            if (std.mem.eql(u8, atom.name, "ping")) {
                std.debug.print("Replying to ping\n", .{});
                var send_buf: c.ei_x_buff = undefined;
                if (c.ei_x_new_with_version(&send_buf) != 0) unreachable;
                if (c.ei_x_encode_atom(&send_buf, "pong") != 0) {
                    return error.EncodingError;
                }
                if (c.ei_send(connection.fd, @constCast(&sender), send_buf.buff, send_buf.index) != 0) {
                    return error.SendError;
                }
                std.debug.print("Succesfully replied to ping\n", .{});
            }
        },
        c.ERL_REG_SEND => @panic("TODO"),
        c.ERL_LINK => @panic("TODO"),
        c.ERL_UNLINK => @panic("TODO"),
        c.ERL_EXIT => @panic("TODO"),
        else => unreachable,
    }
}
