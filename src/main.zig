const std = @import("std");
const Io = std.Io;
const mizu = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const address = Io.net.IpAddress{ .ip4 = Io.net.Ip4Address.loopback(8080) };
    var server = try mizu.Server.init(gpa, io);
    defer server.deinit();

    try server.get("/", indexHandler);
    try server.get("/hello/:name", helloHandler);
    try server.post("/echo", echoHandler);

    var api = server.group("/api");
    try api.get("/users", usersHandler);
    try api.post("/users", createUserHandler);
    try api.onErr(apiErrorHandler);
    try api.get("/error", errorHandler);

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
