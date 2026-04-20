const std = @import("std");
const Io = std.Io;
const mizu = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const address = Io.net.IpAddress{ .ip4 = Io.net.Ip4Address.loopback(8080) };
    var server = try mizu.Server.init(gpa, io);
    defer server.deinit();

    server.get("/").middleware(requestLogger).register();
    server.get("/").handle(indexHandler);
    server.get("/hello/:name").handle(helloHandler);
    server.post("/echo").handle(echoHandler);
    server.get("/protected").middleware(requireApiKey).handle(protectedHandler);

    var api = server.group("/api");
    api.use("*").middleware(apiLogger).register();
    api.get("/users").handle(usersHandler);
    api.post("/users").middleware(requireJson).handle(createUserHandler);
    try api.onErr(apiErrorHandler);
    api.get("/error").handle(errorHandler);

    _ = server.group("/v1");
    try server.onErr(serverErrorHandler);

    std.log.info("Starting server on http://127.0.0.1:8080", .{});
    try server.listen(address);
}

fn indexHandler(ctx: *mizu.Context) anyerror!void {
    _ = try ctx.html("<h1>Welcome to Mizu!</h1><p>A DX-friendly, tiny HTTP framework.</p>");
}

fn helloHandler(ctx: *mizu.Context) anyerror!void {
    const name = ctx.param("name") orelse "World";
    var buf: [100]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "Hello, {s}!", .{name});
    _ = try ctx.text(msg);
}

fn echoHandler(ctx: *mizu.Context) anyerror!void {
    const body = try ctx.body();
    _ = try ctx.json(body);
}

fn protectedHandler(ctx: *mizu.Context) anyerror!void {
    _ = try ctx.json(.{ .ok = true });
}

fn usersHandler(ctx: *mizu.Context) anyerror!void {
    _ = try ctx.json(.{ .users = &.{} });
}

fn createUserHandler(ctx: *mizu.Context) anyerror!void {
    _ = try ctx.json(.{ .created = true });
}

fn postsHandler(ctx: *mizu.Context) anyerror!void {
    _ = try ctx.json(.{ .posts = &.{} });
}

fn postHandler(ctx: *mizu.Context) anyerror!void {
    const id = ctx.param("id") orelse "0";
    _ = try ctx.json(.{ .id = id });
}

fn serverErrorHandler(_: *mizu.Context, _: anyerror) anyerror!void {}

fn apiErrorHandler(_: *mizu.Context, _: anyerror) anyerror!void {
    std.log.err("API error handled", .{});
}

fn errorHandler(ctx: *mizu.Context) anyerror!void {
    _ = ctx;
    return error.TestError;
}

fn requestLogger(ctx: *mizu.Context, next: *mizu.Next) anyerror!void {
    std.log.info("{s} {s}", .{
        @tagName(ctx.request.head.method),
        ctx.request.head.target,
    });
    try next.run();
}

fn apiLogger(ctx: *mizu.Context, next: *mizu.Next) anyerror!void {
    std.log.info("api -> {s}", .{ctx.request.head.target});
    try next.run();
}

fn requireApiKey(ctx: *mizu.Context, next: *mizu.Next) anyerror!void {
    if (ctx.header("x-api-key") == null) {
        try ctx.status(.unauthorized);
        return;
    }

    try next.run();
}

fn requireJson(ctx: *mizu.Context, next: *mizu.Next) anyerror!void {
    const content_type = ctx.header("content-type") orelse "";
    if (std.mem.indexOf(u8, content_type, "application/json") == null) {
        try ctx.status(.unsupported_media_type);
        return;
    }

    try next.run();
}