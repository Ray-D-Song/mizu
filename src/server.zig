const std = @import("std");
const Io = std.Io;

pub const Server = struct {
    pub const Method = enum {
        get,
        post,
        put,
        delete,
        patch,
        options,
        head,
    };

    pub const Handler = *const fn (ctx: *Context) anyerror!void;
    pub const ErrorHandler = *const fn (ctx: *Context, err: anyerror) anyerror!void;

    pub const Route = struct {
        method: Method,
        path: []const u8,
        handler: Handler,
        group: ?*RouterGroup,
    };

    allocator: std.mem.Allocator,
    io: Io,
    routes: std.ArrayList(Route),
    error_handlers: std.ArrayList(ErrorHandler),
    read_buffer: [16384]u8,
    write_buffer: [16384]u8,

    pub fn init(allocator: std.mem.Allocator, io: Io) !Server {
        return .{
            .allocator = allocator,
            .io = io,
            .routes = try std.ArrayList(Route).initCapacity(allocator, 16),
            .error_handlers = try std.ArrayList(ErrorHandler).initCapacity(allocator, 4),
            .read_buffer = undefined,
            .write_buffer = undefined,
        };
    }

    pub fn deinit(server: *Server) void {
        server.routes.deinit(server.allocator);
        server.error_handlers.deinit(server.allocator);
    }

    pub fn onErr(server: *Server, handler: ErrorHandler) !void {
        try server.error_handlers.append(server.allocator, handler);
    }

    pub fn get(server: *Server, path: []const u8, handler: Handler) !void {
        try server.addRoute(.get, path, handler);
    }

    pub fn post(server: *Server, path: []const u8, handler: Handler) !void {
        try server.addRoute(.post, path, handler);
    }

    pub fn put(server: *Server, path: []const u8, handler: Handler) !void {
        try server.addRoute(.put, path, handler);
    }

    pub fn delete(server: *Server, path: []const u8, handler: Handler) !void {
        try server.addRoute(.delete, path, handler);
    }

    pub fn patch(server: *Server, path: []const u8, handler: Handler) !void {
        try server.addRoute(.patch, path, handler);
    }

    pub fn options(server: *Server, path: []const u8, handler: Handler) !void {
        try server.addRoute(.options, path, handler);
    }

    pub fn head(server: *Server, path: []const u8, handler: Handler) !void {
        try server.addRoute(.head, path, handler);
    }

    pub fn group(server: *Server, prefix: []const u8) *RouterGroup {
        const grp = server.allocator.create(RouterGroup) catch unreachable;
        grp.* = .{
            .server = server,
            .prefix = prefix,
            .parent = null,
            .error_handlers = &.{},
        };
        return grp;
    }

    pub const RouterGroup = struct {
        server: *Server,
        prefix: []const u8,
        parent: ?*RouterGroup,
        error_handlers: []ErrorHandler,

        pub fn get(self: *RouterGroup, path: []const u8, handler: Handler) !void {
            const full_path = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path });
            try self.server.addRouteWithGroup(.get, full_path, handler, self);
        }

        pub fn post(self: *RouterGroup, path: []const u8, handler: Handler) !void {
            const full_path = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path });
            try self.server.addRouteWithGroup(.post, full_path, handler, self);
        }

        pub fn put(self: *RouterGroup, path: []const u8, handler: Handler) !void {
            const full_path = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path });
            try self.server.addRouteWithGroup(.put, full_path, handler, self);
        }

        pub fn delete(self: *RouterGroup, path: []const u8, handler: Handler) !void {
            const full_path = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path });
            try self.server.addRouteWithGroup(.delete, full_path, handler, self);
        }

        pub fn patch(self: *RouterGroup, path: []const u8, handler: Handler) !void {
            const full_path = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path });
            try self.server.addRouteWithGroup(.patch, full_path, handler, self);
        }

        pub fn options(self: *RouterGroup, path: []const u8, handler: Handler) !void {
            const full_path = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path });
            try self.server.addRouteWithGroup(.options, full_path, handler, self);
        }

        pub fn head(self: *RouterGroup, path: []const u8, handler: Handler) !void {
            const full_path = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path });
            try self.server.addRouteWithGroup(.head, full_path, handler, self);
        }

        pub fn group(self: *RouterGroup, sub_prefix: []const u8) !*RouterGroup {
            const new_prefix = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, sub_prefix });
            const grp = try self.server.allocator.create(RouterGroup);
            grp.* = .{
                .server = self.server,
                .prefix = new_prefix,
                .parent = self,
                .error_handlers = &.{},
            };
            return grp;
        }

        pub fn onErr(self: *RouterGroup, handler: ErrorHandler) !void {
            const new_handlers = try self.server.allocator.realloc(self.error_handlers, self.error_handlers.len + 1);
            new_handlers[new_handlers.len - 1] = handler;
            self.error_handlers = new_handlers;
        }
    };

    pub fn listen(server: *Server, address: Io.net.IpAddress) !void {
        var net_server = try Io.net.IpAddress.listen(&address, server.io, .{});
        defer net_server.deinit(server.io);

        std.log.info("Server listening on http://127.0.0.1:8080", .{});

        var io_group: Io.Group = .init;
        defer io_group.deinit(server.io);

        while (true) {
            const stream = net_server.accept(server.io) catch |err| {
                std.log.err("accept error: {s}", .{@errorName(err)});
                continue;
            };

            io_group.async(server.io, handleConnectionAsync, .{
                server,
                stream,
            });
        }
    }

    fn addRoute(server: *Server, method: Method, path: []const u8, handler: Handler) !void {
        try server.routes.append(server.allocator, .{
            .method = method,
            .path = path,
            .handler = handler,
            .group = null,
        });
    }

    fn addRouteWithGroup(server: *Server, method: Method, path: []const u8, handler: Handler, grp: *RouterGroup) !void {
        try server.routes.append(server.allocator, .{
            .method = method,
            .path = path,
            .handler = handler,
            .group = grp,
        });
    }

    fn handleConnectionAsync(server: *Server, stream: Io.net.Stream) void {
        defer stream.close(server.io);

        var stream_reader = stream.reader(server.io, &server.read_buffer);
        var stream_writer = stream.writer(server.io, &server.write_buffer);

        var http_server = std.http.Server.init(&stream_reader.interface, &stream_writer.interface);

        var ctx: Context = undefined;
        _ = &ctx;

        while (true) {
            var request = http_server.receiveHead() catch |err| {
                switch (err) {
                    error.HttpConnectionClosing => return,
                    else => {
                        std.log.err("receive head error: {s}", .{@errorName(err)});
                        return;
                    },
                }
            };

            ctx = Context{
                .request = &request,
                .io = server.io,
                .allocator = server.allocator,
                .response_sent = false,
            };

            var matched = false;
            matched = server.dispatch(&ctx) catch |err| {
                std.log.err("dispatch error: {s}", .{@errorName(err)});
                return;
            };

            if (!ctx.response_sent) {
                if (matched) {
                    request.respond("Not Found", .{
                        .status = .not_found,
                    }) catch |err| {
                        std.log.err("respond error: {s}", .{@errorName(err)});
                        return;
                    };
                } else {
                    request.respond("Not Found", .{
                        .status = .not_found,
                    }) catch |err| {
                        std.log.err("respond error: {s}", .{@errorName(err)});
                        return;
                    };
                }
            }
        }
    }

    fn dispatch(server: *Server, ctx: *Context) anyerror!bool {
        const method: Method = switch (ctx.request.head.method) {
            .GET => .get,
            .POST => .post,
            .PUT => .put,
            .DELETE => .delete,
            .PATCH => .patch,
            .OPTIONS => .options,
            .HEAD => .head,
            else => return false,
        };

        const target = ctx.request.head.target;
        const path = if (std.mem.indexOfScalar(u8, target, '?')) |q| target[0..q] else target;

        for (server.routes.items) |route| {
            if (route.method == method) {
                if (std.mem.eql(u8, route.path, path)) {
                    ctx.param_value = null;
                    ctx.param_match_value = null;
                    server.runHandler(route.handler, ctx, route.group);
                    return true;
                }

                if (matchPathWithParams(route.path, path, ctx)) {
                    server.runHandler(route.handler, ctx, route.group);
                    return true;
                }
            }
        }

        return false;
    }

    fn runHandler(server: *Server, handler: Handler, ctx: *Context, grp: ?*RouterGroup) void {
        handler(ctx) catch |err| {
            server.handleError(ctx, err, grp);
        };
    }

    fn handleError(server: *Server, ctx: *Context, err: anyerror, grp: ?*RouterGroup) void {
        if (grp) |g| {
            for (g.error_handlers) |h| {
                h(ctx, err) catch |e| {
                    server.handleError(ctx, e, g.parent);
                    return;
                };
            }
        } else {
            for (server.error_handlers.items) |h| {
                h(ctx, err) catch |e| {
                    std.log.err("unhandled error: {s}", .{@errorName(e)});
                };
            }
        }
    }

    fn matchPathWithParams(route_path: []const u8, request_path: []const u8, ctx: *Context) bool {
        var route_iter = std.mem.splitScalar(u8, route_path, '/');
        var path_iter = std.mem.splitScalar(u8, request_path, '/');

        while (route_iter.next()) |route_seg| {
            const path_seg = path_iter.next() orelse return false;

            if (route_seg.len == 0) {
                if (path_seg.len != 0) return false;
                continue;
            }

            if (route_seg[0] == ':') {
                ctx.param_value = route_seg[1..];
                ctx.param_match_value = path_seg;
            } else if (!std.mem.eql(u8, route_seg, path_seg)) {
                return false;
            }
        }

        return path_iter.next() == null;
    }
};

pub const Context = struct {
    request: *std.http.Server.Request,
    io: Io,
    allocator: std.mem.Allocator,
    response_sent: bool,
    param_value: ?[]const u8 = null,
    param_match_value: ?[]const u8 = null,

    pub fn text(ctx: *Context, content: []const u8) anyerror!void {
        try ctx.request.respond(content, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/plain" },
            },
        });
        ctx.response_sent = true;
    }

    pub fn json(ctx: *Context, value: anytype) anyerror!void {
        const json_str = try std.json.Stringify.valueAlloc(ctx.allocator, value, .{});
        defer ctx.allocator.free(json_str);

        try ctx.request.respond(json_str, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
        ctx.response_sent = true;
    }

    pub fn html(ctx: *Context, content: []const u8) anyerror!void {
        try ctx.request.respond(content, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html" },
            },
        });
        ctx.response_sent = true;
    }

    pub fn raw(ctx: *Context, content: []const u8, content_type: []const u8) anyerror!void {
        try ctx.request.respond(content, .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "content-type", .value = content_type },
            },
        });
        ctx.response_sent = true;
    }

    pub fn notFound(ctx: *Context, content: []const u8) anyerror!void {
        try ctx.request.respond(content, .{
            .status = .not_found,
        });
        ctx.response_sent = true;
    }

    pub fn status(ctx: *Context, code: std.http.Status) anyerror!void {
        const phrase = code.phrase() orelse "";
        try ctx.request.respond(phrase, .{
            .status = code,
        });
        ctx.response_sent = true;
    }

    pub fn param(ctx: *Context, name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, name, ctx.param_value orelse return null)) {
            return ctx.param_match_value;
        }
        return null;
    }

    pub fn query(ctx: *Context, name: []const u8) ?[]const u8 {
        const target = ctx.request.head.target;
        if (std.mem.indexOfScalar(u8, target, '?')) |q_idx| {
            const query_string = target[q_idx + 1 ..];
            var iter = std.mem.splitScalar(u8, query_string, '&');
            while (iter.next()) |pair| {
                if (std.mem.indexOfScalar(u8, pair, '=')) |eq_idx| {
                    const key = pair[0..eq_idx];
                    if (std.mem.eql(u8, key, name)) {
                        return pair[eq_idx + 1 ..];
                    }
                }
            }
        }
        return null;
    }

    pub fn body(ctx: *Context) anyerror![]const u8 {
        const len = ctx.request.head.content_length orelse return "";
        if (len == 0) return "";

        var body_buf: [8192]u8 = undefined;
        const body_reader = ctx.request.readerExpectNone(&body_buf);
        if (body_reader == Io.Reader.ending) return "";

        const content = try ctx.allocator.alloc(u8, len);
        errdefer ctx.allocator.free(content);

        var remaining = content;
        while (remaining.len > 0) {
            var data: [1][]u8 = .{remaining};
            const n = try body_reader.readVec(&data);
            remaining = remaining[n..];
        }
        return content;
    }

    pub fn header(ctx: *Context, name: []const u8) ?[]const u8 {
        var iter = ctx.request.iterateHeaders();
        while (iter.next()) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                return h.value;
            }
        }
        return null;
    }
};
