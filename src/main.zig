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

    std.log.info("Starting server on http://127.0.0.1:8080", .{});
    try server.listen(address);
}

fn indexHandler(ctx: *mizu.Context) !void {
    try ctx.html("<h1>Welcome to Mizu!</h1><p>A DX-friendly, tiny HTTP framework.</p>");
}

fn helloHandler(ctx: *mizu.Context) !void {
    const name = ctx.param("name") orelse "World";
    var buf: [100]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "Hello, {s}!", .{name});
    try ctx.text(msg);
}

fn echoHandler(ctx: *mizu.Context) !void {
    const body = try ctx.body();
    try ctx.json(body);
}
