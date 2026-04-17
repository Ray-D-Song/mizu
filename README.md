# Mizu

A DX-friendly, tiny HTTP framework for Zig 0.16+, inspired by Hono.

Built on top of Zig's new [I/O as an Interface](https://ziglang.org/download/0.16.0/release-notes.html#IO-as-an-Interface) API.

## Quick Start

```zig
const std = @import("std");
const Io = std.Io;
const mizu = @import("mizu");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var server = try mizu.Server.init(gpa, io);
    defer server.deinit();

    try server.get("/", handler);

    const address = Io.net.IpAddress{ .ip4 = Io.net.Ip4Address.loopback(8080) };
    try server.listen(address);
}

fn handler(ctx: *mizu.Context) anyerror!void {
    try ctx.json(.{ .message = "Hello Mizu!" });
}
```

## Architecture

Mizu uses Zig 0.16's new IO features:

- **Io.Group.async** - Handles each connection asynchronously
- **Io.net.Stream** - Modern network stream API
- **Io.Reader/Io.Writer** - Interface-based I/O

## Context Methods

### Response Methods

```zig
try ctx.text("Hello");           // text/plain
try ctx.html("<h1>Title</h1>"); // text/html
try ctx.json(.{ .key = "value" }); // anonymous struct -> json
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