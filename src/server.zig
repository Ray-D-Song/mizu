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

    const Param = struct {
        name: []const u8,
        value: []const u8,
    };

    const ParamStore = struct {
        items: [16]Param = undefined,
        len: usize = 0,

        fn put(params: *ParamStore, name: []const u8, value: []const u8) void {
            for (params.items[0..params.len]) |*item| {
                if (std.mem.eql(u8, item.name, name)) {
                    item.value = value;
                    return;
                }
            }

            if (params.len == params.items.len) return;

            params.items[params.len] = .{
                .name = name,
                .value = value,
            };
            params.len += 1;
        }

        fn merge(params: *ParamStore, other: ParamStore) void {
            for (other.items[0..other.len]) |item| {
                params.put(item.name, item.value);
            }
        }
    };

    pub const Handler = *const fn (ctx: *Context) anyerror!void;

    pub const Next = struct {
        ctx: *Context,
        middlewares: []const Middleware,
        handler: ?Handler,
        index: usize = 0,

        pub fn run(next: *Next) anyerror!void {
            if (next.index < next.middlewares.len) {
                const middleware = next.middlewares[next.index];
                var downstream = next.*;
                downstream.index += 1;
                try middleware(next.ctx, &downstream);
                return;
            }

            if (next.handler) |handler| {
                try handler(next.ctx);
            }
        }
    };

    pub const Middleware = *const fn (ctx: *Context, next: *Next) anyerror!void;
    pub const ErrorHandler = *const fn (ctx: *Context, err: anyerror) anyerror!void;

    pub const Route = struct {
        method: ?Method,
        path: []const u8,
        owns_path: bool,
        middlewares: []Middleware,
        handler: ?Handler,
        group: ?*RouterGroup,
    };

    const RouteCallbacks = struct {
        middlewares: []Middleware,
        handler: ?Handler,
    };

    pub const RouteBuilder = struct {
        server: *Server,
        method: Method,
        path: []const u8,
        owns_path: bool,
        middlewares: []Middleware = &.{},
        handler: ?Handler = null,
        group: ?*RouterGroup = null,

        pub fn middleware(self: *RouteBuilder, mw: Middleware) *RouteBuilder {
            self.middlewares = self.server.appendMiddlewares(self.middlewares, mw);
            return self;
        }

        pub fn handle(self: *RouteBuilder, h: Handler) void {
            self.server.routes.append(self.server.allocator, .{
                .method = self.method,
                .path = self.path,
                .owns_path = self.owns_path,
                .middlewares = self.middlewares,
                .handler = h,
                .group = self.group,
            }) catch unreachable;
        }

        pub fn register(self: *RouteBuilder) void {
            self.server.routes.append(self.server.allocator, .{
                .method = self.method,
                .path = self.path,
                .owns_path = self.owns_path,
                .middlewares = self.middlewares,
                .handler = null,
                .group = self.group,
            }) catch unreachable;
        }

        fn appendMiddlewares(self: *RouteBuilder, initial: []Middleware, mw: Middleware) []Middleware {
            var result = self.server.allocator.alloc(Middleware, initial.len + 1) catch unreachable;
            @memcpy(result[0..initial.len], initial);
            result[initial.len] = mw;
            return result;
        }
    };

    pub const GroupBuilder = struct {
        server: *Server,
        prefix: []const u8,
        path: ?[]const u8 = null,
        method: ?Method = null,
        owns_path: bool = false,
        middlewares: []Middleware = &.{},
        has_handler: bool = false,
        handler: ?Handler = null,
        group: *RouterGroup,

        pub fn use(self: *GroupBuilder, mw: Middleware) void {
            const new_mws = self.server.appendMiddlewares(self.middlewares, mw);
            self.server.routes.append(self.server.allocator, .{
                .method = null,
                .path = "*",
                .owns_path = false,
                .middlewares = new_mws,
                .handler = null,
                .group = self.group,
            }) catch unreachable;
        }

        pub fn get(self: *GroupBuilder, path: []const u8) *GroupBuilder {
            self.method = .get;
            self.path = self.combinePath(path);
            return self;
        }

        pub fn post(self: *GroupBuilder, path: []const u8) *GroupBuilder {
            self.method = .post;
            self.path = self.combinePath(path);
            return self;
        }

        pub fn put(self: *GroupBuilder, path: []const u8) *GroupBuilder {
            self.method = .put;
            self.path = self.combinePath(path);
            return self;
        }

        pub fn delete(self: *GroupBuilder, path: []const u8) *GroupBuilder {
            self.method = .delete;
            self.path = self.combinePath(path);
            return self;
        }

        pub fn patch(self: *GroupBuilder, path: []const u8) *GroupBuilder {
            self.method = .patch;
            self.path = self.combinePath(path);
            return self;
        }

        pub fn options(self: *GroupBuilder, path: []const u8) *GroupBuilder {
            self.method = .options;
            self.path = self.combinePath(path);
            return self;
        }

        pub fn head(self: *GroupBuilder, path: []const u8) *GroupBuilder {
            self.method = .head;
            self.path = self.combinePath(path);
            return self;
        }

        pub fn middleware(self: *GroupBuilder, mw: Middleware) *GroupBuilder {
            self.middlewares = self.server.appendMiddlewares(self.middlewares, mw);
            return self;
        }

        pub fn handle(self: *GroupBuilder, h: Handler) void {
            self.server.routes.append(self.server.allocator, .{
                .method = self.method,
                .path = self.path.?,
                .owns_path = self.owns_path,
                .middlewares = self.middlewares,
                .handler = h,
                .group = self.group,
            }) catch unreachable;
        }

        pub fn register(self: *GroupBuilder) void {
            self.server.routes.append(self.server.allocator, .{
                .method = self.method,
                .path = self.path.?,
                .owns_path = self.owns_path,
                .middlewares = self.middlewares,
                .handler = self.handler,
                .group = self.group,
            }) catch unreachable;
        }

        fn combinePath(self: *GroupBuilder, path: []const u8) []const u8 {
            return std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path }) catch unreachable;
        }

        fn appendMiddlewares(self: *GroupBuilder, initial: []Middleware, mw: Middleware) []Middleware {
            var result = self.server.allocator.alloc(Middleware, initial.len + 1) catch unreachable;
            @memcpy(result[0..initial.len], initial);
            result[initial.len] = mw;
            return result;
        }
    };

    pub const GroupUseBuilder = struct {
        server: *Server,
        prefix: []const u8,
        middlewares: []Middleware = &.{},
        group: *RouterGroup,

        pub fn middleware(self: *GroupUseBuilder, mw: Middleware) *GroupUseBuilder {
            self.middlewares = self.server.appendMiddlewares(self.middlewares, mw);
            return self;
        }

        pub fn register(self: *GroupUseBuilder) void {
            self.server.routes.append(self.server.allocator, .{
                .method = null,
                .path = self.prefix,
                .owns_path = false,
                .middlewares = self.middlewares,
                .handler = null,
                .group = self.group,
            }) catch unreachable;
        }

        fn appendMiddlewares(self: *GroupUseBuilder, initial: []Middleware, mw: Middleware) []Middleware {
            var result = self.server.allocator.alloc(Middleware, initial.len + 1) catch unreachable;
            @memcpy(result[0..initial.len], initial);
            result[initial.len] = mw;
            return result;
        }
    };

    const UseCallbacks = struct {
        path: []const u8,
        owns_path: bool,
        middlewares: []Middleware,
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
        for (server.routes.items) |route| {
            if (route.owns_path) {
                server.allocator.free(route.path);
            }
            server.allocator.free(route.middlewares);
        }

        server.routes.deinit(server.allocator);
        server.error_handlers.deinit(server.allocator);
    }

    pub fn onErr(server: *Server, handler: ErrorHandler) !void {
        try server.error_handlers.append(server.allocator, handler);
    }

    pub fn use(server: *Server, callbacks: anytype) !void {
        try server.addUse(callbacks, null, null);
    }

    pub fn get(server: *Server, path: []const u8) *RouteBuilder {
        const builder = server.allocator.create(RouteBuilder) catch unreachable;
        builder.* = .{
            .server = server,
            .method = .get,
            .path = path,
            .owns_path = false,
        };
        return builder;
    }

    pub fn post(server: *Server, path: []const u8) *RouteBuilder {
        const builder = server.allocator.create(RouteBuilder) catch unreachable;
        builder.* = .{
            .server = server,
            .method = .post,
            .path = path,
            .owns_path = false,
        };
        return builder;
    }

    pub fn put(server: *Server, path: []const u8) *RouteBuilder {
        const builder = server.allocator.create(RouteBuilder) catch unreachable;
        builder.* = .{
            .server = server,
            .method = .put,
            .path = path,
            .owns_path = false,
        };
        return builder;
    }

    pub fn delete(server: *Server, path: []const u8) *RouteBuilder {
        const builder = server.allocator.create(RouteBuilder) catch unreachable;
        builder.* = .{
            .server = server,
            .method = .delete,
            .path = path,
            .owns_path = false,
        };
        return builder;
    }

    pub fn patch(server: *Server, path: []const u8) *RouteBuilder {
        const builder = server.allocator.create(RouteBuilder) catch unreachable;
        builder.* = .{
            .server = server,
            .method = .patch,
            .path = path,
            .owns_path = false,
        };
        return builder;
    }

    pub fn options(server: *Server, path: []const u8) *RouteBuilder {
        const builder = server.allocator.create(RouteBuilder) catch unreachable;
        builder.* = .{
            .server = server,
            .method = .options,
            .path = path,
            .owns_path = false,
        };
        return builder;
    }

    pub fn head(server: *Server, path: []const u8) *RouteBuilder {
        const builder = server.allocator.create(RouteBuilder) catch unreachable;
        builder.* = .{
            .server = server,
            .method = .head,
            .path = path,
            .owns_path = false,
        };
        return builder;
    }

    fn appendMiddlewares(server: *Server, initial: []Middleware, mw: Middleware) []Middleware {
        var result = server.allocator.alloc(Middleware, initial.len + 1) catch unreachable;
        @memcpy(result[0..initial.len], initial);
        result[initial.len] = mw;
        return result;
    }

    pub fn group(server: *Server, prefix: []const u8) *RouterGroup {
        const handlers = std.ArrayList(ErrorHandler).initCapacity(server.allocator, 4) catch unreachable;
        const grp = server.allocator.create(RouterGroup) catch unreachable;
        grp.* = .{
            .server = server,
            .prefix = prefix,
            .parent = null,
            .error_handlers = handlers,
        };
        return grp;
    }

    pub const RouterGroup = struct {
        server: *Server,
        prefix: []const u8,
        parent: ?*RouterGroup,
        error_handlers: std.ArrayList(ErrorHandler),

        pub fn use(self: *RouterGroup, path: []const u8) *GroupUseBuilder {
            const builder = self.server.allocator.create(GroupUseBuilder) catch unreachable;
            builder.* = .{
                .server = self.server,
                .prefix = path,
                .middlewares = &.{},
                .group = self,
            };
            return builder;
        }

        pub fn get(self: *RouterGroup, path: []const u8) *GroupBuilder {
            const builder = self.server.allocator.create(GroupBuilder) catch unreachable;
            builder.* = .{
                .server = self.server,
                .prefix = self.prefix,
                .path = std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path }) catch unreachable,
                .method = .get,
                .middlewares = &.{},
                .group = self,
            };
            return builder;
        }

        pub fn post(self: *RouterGroup, path: []const u8) *GroupBuilder {
            const builder = self.server.allocator.create(GroupBuilder) catch unreachable;
            builder.* = .{
                .server = self.server,
                .prefix = self.prefix,
                .path = std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path }) catch unreachable,
                .method = .post,
                .middlewares = &.{},
                .group = self,
            };
            return builder;
        }

        pub fn put(self: *RouterGroup, path: []const u8) *GroupBuilder {
            const builder = self.server.allocator.create(GroupBuilder) catch unreachable;
            builder.* = .{
                .server = self.server,
                .prefix = self.prefix,
                .path = std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path }) catch unreachable,
                .method = .put,
                .middlewares = &.{},
                .group = self,
            };
            return builder;
        }

        pub fn delete(self: *RouterGroup, path: []const u8) *GroupBuilder {
            const builder = self.server.allocator.create(GroupBuilder) catch unreachable;
            builder.* = .{
                .server = self.server,
                .prefix = self.prefix,
                .path = std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path }) catch unreachable,
                .method = .delete,
                .middlewares = &.{},
                .group = self,
            };
            return builder;
        }

        pub fn patch(self: *RouterGroup, path: []const u8) *GroupBuilder {
            const builder = self.server.allocator.create(GroupBuilder) catch unreachable;
            builder.* = .{
                .server = self.server,
                .prefix = self.prefix,
                .path = std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path }) catch unreachable,
                .method = .patch,
                .middlewares = &.{},
                .group = self,
            };
            return builder;
        }

        pub fn options(self: *RouterGroup, path: []const u8) *GroupBuilder {
            const builder = self.server.allocator.create(GroupBuilder) catch unreachable;
            builder.* = .{
                .server = self.server,
                .prefix = self.prefix,
                .path = std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path }) catch unreachable,
                .method = .options,
                .middlewares = &.{},
                .group = self,
            };
            return builder;
        }

        pub fn head(self: *RouterGroup, path: []const u8) *GroupBuilder {
            const builder = self.server.allocator.create(GroupBuilder) catch unreachable;
            builder.* = .{
                .server = self.server,
                .prefix = self.prefix,
                .path = std.mem.concat(self.server.allocator, u8, &.{ self.prefix, path }) catch unreachable,
                .method = .head,
                .middlewares = &.{},
                .group = self,
            };
            return builder;
        }

        pub fn group(self: *RouterGroup, sub_prefix: []const u8) !*RouterGroup {
            const new_prefix = try std.mem.concat(self.server.allocator, u8, &.{ self.prefix, sub_prefix });
            errdefer self.server.allocator.free(new_prefix);

            const handlers = std.ArrayList(ErrorHandler).initCapacity(self.server.allocator, 4) catch unreachable;

            const grp = try self.server.allocator.create(RouterGroup);
            grp.* = .{
                .server = self.server,
                .prefix = new_prefix,
                .parent = self,
                .error_handlers = handlers,
            };
            return grp;
        }

        pub fn onErr(self: *RouterGroup, handler: ErrorHandler) !void {
            try self.error_handlers.append(self.server.allocator, handler);
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

    fn addRoute(server: *Server, method: Method, path: []const u8, owns_path: bool, callbacks: anytype, grp: ?*RouterGroup) !void {
        const route_callbacks = try server.normalizeRouteCallbacks(callbacks);
        errdefer server.allocator.free(route_callbacks.middlewares);

        try server.routes.append(server.allocator, .{
            .method = method,
            .path = path,
            .owns_path = owns_path,
            .middlewares = route_callbacks.middlewares,
            .handler = route_callbacks.handler,
            .group = grp,
        });
    }

    fn addUse(server: *Server, callbacks: anytype, prefix: ?[]const u8, grp: ?*RouterGroup) !void {
        const use_callbacks = try server.normalizeUseCallbacks(callbacks, prefix);
        errdefer {
            if (use_callbacks.owns_path) {
                server.allocator.free(use_callbacks.path);
            }
            server.allocator.free(use_callbacks.middlewares);
        }

        try server.routes.append(server.allocator, .{
            .method = null,
            .path = use_callbacks.path,
            .owns_path = use_callbacks.owns_path,
            .middlewares = use_callbacks.middlewares,
            .handler = null,
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
            };
            defer ctx.deinit();

            const matched = server.dispatch(&ctx) catch |err| {
                std.log.err("dispatch error: {s}", .{@errorName(err)});
                return;
            };

            if (!ctx.response_sent) {
                const status: std.http.Status = if (matched) .not_found else .not_found;
                request.respond("Not Found", .{
                    .status = status,
                }) catch |err| {
                    std.log.err("respond error: {s}", .{@errorName(err)});
                    return;
                };
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

        var chain = std.ArrayList(Middleware).initCapacity(server.allocator, 4) catch unreachable;
        defer chain.deinit(server.allocator);

        var params = ParamStore{};

        for (server.routes.items) |route| {
            if (route.method) |route_method| {
                if (route_method != method) continue;
            }

            var route_params = ParamStore{};
            if (!matchPathPattern(route.path, path, &route_params)) continue;

            if (route.middlewares.len > 0) {
                try chain.appendSlice(server.allocator, route.middlewares);
            }
            params.merge(route_params);

            if (route.handler) |handler| {
                ctx.setParams(params);
                server.runChain(chain.items, handler, ctx, route.group);
                return true;
            }
        }

        return false;
    }

    fn runChain(server: *Server, middlewares: []const Middleware, handler: Handler, ctx: *Context, grp: ?*RouterGroup) void {
        var next = Next{
            .ctx = ctx,
            .middlewares = middlewares,
            .handler = handler,
        };

        next.run() catch |err| {
            server.handleError(ctx, err, grp);
        };
    }

    fn handleError(server: *Server, ctx: *Context, err: anyerror, grp: ?*RouterGroup) void {
        if (grp) |g| {
            for (g.error_handlers.items) |h| {
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

    fn normalizeRouteCallbacks(server: *Server, callbacks: anytype) !RouteCallbacks {
        const T = @TypeOf(callbacks);

        if (comptime isTuple(T)) {
            return try server.normalizeRouteTuple(callbacks);
        }

        const kind = comptime callbackKind(T);
        return switch (kind) {
            .handler => .{
                .middlewares = try server.allocator.alloc(Middleware, 0),
                .handler = callbacks,
            },
            .middleware => .{
                .middlewares = try server.copyMiddlewares(&.{@as(Middleware, callbacks)}),
                .handler = null,
            },
        };
    }

    fn normalizeRouteTuple(server: *Server, callbacks: anytype) !RouteCallbacks {
        const fields = std.meta.fields(@TypeOf(callbacks));
        if (fields.len == 0) {
            @compileError("Route registration requires at least one handler or middleware.");
        }

        const last_index = fields.len - 1;
        const has_handler = comptime callbackKind(@TypeOf(callbacks[last_index])) == .handler;
        const middleware_count = if (has_handler) last_index else fields.len;

        if (has_handler and comptime callbackKind(fields[last_index].type) != .handler) {
            @compileError("The last route callback must be a handler.");
        }

        inline for (0..middleware_count) |index| {
            if (comptime callbackKind(fields[index].type) != .middleware) {
                @compileError("Route middlewares must have the signature fn (*Context, *Next) anyerror!void.");
            }
        }

        var middlewares = try server.allocator.alloc(Middleware, middleware_count);
        inline for (0..middleware_count) |index| {
            middlewares[index] = callbacks[index];
        }

        return .{
            .middlewares = middlewares,
            .handler = if (has_handler) callbacks[last_index] else null,
        };
    }

    fn normalizeUseCallbacks(server: *Server, callbacks: anytype, prefix: ?[]const u8) !UseCallbacks {
        const T = @TypeOf(callbacks);

        if (comptime !isTuple(T)) {
            const path = try server.scopeMiddlewarePath("*", prefix);
            return .{
                .path = path.path,
                .owns_path = path.owns_path,
                .middlewares = try server.copyMiddlewares(&.{@as(Middleware, callbacks)}),
            };
        }

        const fields = std.meta.fields(T);
        if (fields.len == 0) {
            @compileError("use() requires at least one middleware.");
        }

        const first_is_path = comptime isStringLike(fields[0].type);
        const middleware_start: usize = if (first_is_path) 1 else 0;

        if (middleware_start == fields.len) {
            @compileError("use() requires at least one middleware.");
        }

        inline for (middleware_start..fields.len) |index| {
            if (comptime callbackKind(fields[index].type) != .middleware) {
                @compileError("use() only accepts middleware callbacks.");
            }
        }

        const base_path = if (first_is_path) asPath(callbacks[0]) else "*";
        const scoped_path = try server.scopeMiddlewarePath(base_path, prefix);
        errdefer if (scoped_path.owns_path) server.allocator.free(scoped_path.path);

        var middlewares = try server.allocator.alloc(Middleware, fields.len - middleware_start);
        errdefer server.allocator.free(middlewares);

        inline for (middleware_start..fields.len, 0..) |index, dest_index| {
            middlewares[dest_index] = callbacks[index];
        }

        return .{
            .path = scoped_path.path,
            .owns_path = scoped_path.owns_path,
            .middlewares = middlewares,
        };
    }

    fn copyMiddlewares(server: *Server, middlewares: []const Middleware) ![]Middleware {
        const copy = try server.allocator.alloc(Middleware, middlewares.len);
        @memcpy(copy, middlewares);
        return copy;
    }

    fn scopeMiddlewarePath(server: *Server, base_path: []const u8, prefix: ?[]const u8) !struct { path: []const u8, owns_path: bool } {
        if (prefix == null) {
            return .{
                .path = base_path,
                .owns_path = false,
            };
        }

        if (std.mem.eql(u8, base_path, "*")) {
            if (std.mem.eql(u8, prefix.?, "/")) {
                return .{
                    .path = "*",
                    .owns_path = false,
                };
            }

            return .{
                .path = try ensureWildcardPath(server.allocator, prefix.?),
                .owns_path = true,
            };
        }

        return .{
            .path = try std.mem.concat(server.allocator, u8, &.{ prefix.?, base_path }),
            .owns_path = true,
        };
    }

    fn ensureWildcardPath(allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
        if (std.mem.eql(u8, prefix, "/")) {
            return allocator.dupe(u8, "*");
        }

        if (std.mem.endsWith(u8, prefix, "/*")) {
            return allocator.dupe(u8, prefix);
        }

        if (prefix.len > 0 and prefix[prefix.len - 1] == '/') {
            return std.mem.concat(allocator, u8, &.{ prefix, "*" });
        }

        return std.mem.concat(allocator, u8, &.{ prefix, "/*" });
    }

    const CallbackKind = enum {
        handler,
        middleware,
    };

    fn callbackKind(comptime T: type) CallbackKind {
        const fn_info = functionInfo(T);

        return switch (fn_info.params.len) {
            1 => .handler,
            2 => .middleware,
            else => @compileError("Callbacks must have the signature fn (*Context) anyerror!void or fn (*Context, *Next) anyerror!void."),
        };
    }

    fn functionInfo(comptime T: type) std.builtin.Type.Fn {
        return switch (@typeInfo(T)) {
            .@"fn" => |info| info,
            .pointer => |ptr| switch (@typeInfo(ptr.child)) {
                .@"fn" => |info| info,
                else => @compileError("Expected a function pointer."),
            },
            else => @compileError("Expected a function."),
        };
    }

    fn isTuple(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .@"struct" => |info| info.is_tuple,
            else => false,
        };
    }

    fn isStringLike(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .pointer => |ptr| ptr.size == .slice and ptr.child == u8,
            .array => |array| array.child == u8,
            else => blk: {
                if (@typeInfo(T) == .pointer) {
                    const ptr = @typeInfo(T).pointer;
                    switch (@typeInfo(ptr.child)) {
                        .array => |array| break :blk array.child == u8,
                        else => break :blk false,
                    }
                }
                break :blk false;
            },
        };
    }

    fn asPath(path: anytype) []const u8 {
        return switch (@typeInfo(@TypeOf(path))) {
            .pointer => |ptr| switch (ptr.size) {
                .slice => path,
                .one => std.mem.span(path),
                else => @compileError("Invalid path type."),
            },
            .array => path[0..],
            else => @compileError("Invalid path type."),
        };
    }

    fn matchPathPattern(pattern: []const u8, request_path: []const u8, params: *ParamStore) bool {
        if (std.mem.eql(u8, pattern, "*")) return true;

        var pattern_iter = std.mem.splitScalar(u8, pattern, '/');
        var path_iter = std.mem.splitScalar(u8, request_path, '/');

        while (pattern_iter.next()) |pattern_seg| {
            if (std.mem.eql(u8, pattern_seg, "*")) {
                return true;
            }

            const path_seg = path_iter.next() orelse return false;

            if (pattern_seg.len == 0) {
                if (path_seg.len != 0) return false;
                continue;
            }

            if (pattern_seg[0] == ':') {
                params.put(pattern_seg[1..], path_seg);
                continue;
            }

            if (!std.mem.eql(u8, pattern_seg, path_seg)) {
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
    response_sent: bool = false,
    params: [16]Server.Param = undefined,
    param_count: usize = 0,
    cached_body: ?[]u8 = null,

    fn deinit(ctx: *Context) void {
        if (ctx.cached_body) |cached| {
            ctx.allocator.free(cached);
        }
    }

    fn setParams(ctx: *Context, params: Server.ParamStore) void {
        ctx.param_count = params.len;
        for (params.items[0..params.len], 0..) |item, index| {
            ctx.params[index] = item;
        }
    }

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
        for (ctx.params[0..ctx.param_count]) |captured_param| {
            if (std.mem.eql(u8, captured_param.name, name)) {
                return captured_param.value;
            }
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
        if (ctx.cached_body) |cached| return cached;

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

        ctx.cached_body = content;
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

test "middleware path wildcard matches exact prefix and children" {
    var params = Server.ParamStore{};
    try std.testing.expect(Server.matchPathPattern("/api/*", "/api", &params));
    try std.testing.expect(Server.matchPathPattern("/api/*", "/api/users", &params));
    try std.testing.expect(!Server.matchPathPattern("/api/*", "/v1/users", &params));
}

test "path params are captured across segments" {
    var params = Server.ParamStore{};
    try std.testing.expect(Server.matchPathPattern("/users/:id/posts/:post_id", "/users/42/posts/99", &params));
    try std.testing.expectEqualStrings("42", params.items[0].value);
    try std.testing.expectEqualStrings("99", params.items[1].value);
}
