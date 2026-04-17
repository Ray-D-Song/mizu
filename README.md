# Mizu

A DX-friendly, tiny HTTP framework for Zig 0.16+, inspired by Hono.

Built on top of Zig's new [I/O as an Interface](https://ziglang.org/download/0.16.0/release-notes.html#IO-as-an-Interface) API.

## Quick Start

```zig
const std = @import("std");
const mizu = @import("mizu");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var server = try zray.Server.init(gpa, io);
    defer server.deinit();

    try server.get("/", indexHandler);
    try server.get("/hello/:name", helloHandler);
    try server.post("/echo", echoHandler);

    const address = Io.net.IpAddress{ .ip4 = Io.net.Ip4Address.loopback(8080) };
    try server.listen(address);
}

fn indexHandler(ctx: *zray.Context) !void {
    try ctx.html("<h1>Welcome to Zray!</h1>");
}

fn helloHandler(ctx: *zray.Context) !void {
    const name = ctx.param("name") orelse "World";
    var buf: [100]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "Hello, {s}!", .{name});
    try ctx.text(msg);
}

fn echoHandler(ctx: *zray.Context) !void {
    const body = try ctx.body();
    try ctx.json(body);
}
```

## Context Methods

### Response Methods

```zig
try ctx.text("Hello");           // text/plain
try ctx.html("<h1>Title</h1>"); // text/html
try ctx.json("{\"key\":\"value\"}"); // application/json
try ctx.raw(bytes, "application/octet-stream");
try ctx.status(.not_found);
```

### Request Helpers

```zig
const name = ctx.param("name");     // URL path parameter
const value = ctx.query("key");      // Query string parameter
const body = try ctx.body();        // Request body
const header = ctx.header("Content-Type"); // Request header
```

## Routing

```zig
// Static routes
try server.get("/", handler);
try server.post("/submit", handler);

// Path parameters (prefixed with :)
try server.get("/users/:id", handler);
try server.get("/articles/:year/:month", handler);
```

## Supported HTTP Methods

- `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, `HEAD`

## Requirements

- Zig 0.16.0 or later
