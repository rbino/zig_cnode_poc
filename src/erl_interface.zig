const std = @import("std");

pub const c = @cImport({
    @cInclude("ei.h");
    @cInclude("ei_connect.h");
});

pub fn init() !void {
    if (c.ei_init() != 0) return error.InitError;
}

pub const Pid = c.erlang_pid;

pub const CNode = struct {
    ec: c.ei_cnode,
    fd: c_int,

    pub fn init(this_node_name: [:0]const u8, cookie: ?[:0]const u8, creation: u32) !CNode {
        // Do this to cast from ?[:0]const u8 to [*c]const u8
        const _cookie: [*c]const u8 = cookie orelse null;
        var ret = CNode{ .ec = undefined, .fd = undefined };
        ret.fd = c.ei_connect_init(&ret.ec, this_node_name, _cookie, creation);
        if (ret.fd < 0) {
            return error.CNodeInitError;
        }
        return ret;
    }

    pub fn listen(self: *CNode, backlog: c_int) !Server {
        var port: c_int = 0;
        const fd = c.ei_listen(&self.ec, &port, backlog);
        if (fd < 0) {
            return error.ListenError;
        }
        return Server{ .ec_ptr = &self.ec, .sock_fd = fd, .port = port };
    }

    pub fn self_pid(self: *CNode) *Pid {
        return c.ei_self(&self.ec);
    }
};

pub const Server = struct {
    ec_ptr: *c.ei_cnode,
    sock_fd: c_int,
    port: c_int,
    epmd_fd: c_int = undefined,

    pub fn publish(self: *Server) !void {
        const fd = c.ei_publish(self.ec_ptr, self.port);
        if (fd < 0) {
            return error.PublishError;
        }
        self.epmd_fd = fd;
    }

    pub fn unpublish(self: *Server) void {
        std.os.close(self.epmd_fd);
    }

    pub fn accept(self: Server) !Connection {
        // TODO: copy node name from here to Connection
        var conn: c.ErlConnect = undefined;
        const fd = c.ei_accept(self.ec_ptr, self.sock_fd, &conn);
        if (fd < 0) {
            return error.AcceptError;
        }
        return Connection{ .fd = fd };
    }

    pub fn close(self: Server) void {
        _ = c.ei_close_connection(self.sock_fd);
    }
};

pub const Connection = struct {
    fd: c_int,

    pub fn register(self: Connection, name: [:0]const u8, pid: *Pid) !void {
        if (c.ei_global_register(self.fd, name, pid) != 0) {
            return error.RegisterError;
        }
    }

    pub fn receive(self: Connection, buf: []u8) []u8 {
        _ = self;
        return buf;
    }

    pub fn close(self: Connection) void {
        _ = c.ei_close_connection(self.fd);
    }
};
