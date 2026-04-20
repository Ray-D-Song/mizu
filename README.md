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

    server.get("/").handle(handler);
    server.get("/protected").middleware(requireApiKey).handle(protectedHandler);

    const address = Io.net.IpAddress{ .ip4 = Io.net.Ip4Address.loopback(8080) };
    try server.listen(address);
}

fn handler(ctx: *mizu.Context) anyerror!void {
    try ctx.json(.{ .message = "Hello Mizu!" });
}

fn protectedHandler(ctx: *mizu.Context) anyerror!void {
    try ctx.text("ok");
}

fn requireApiKey(ctx: *mizu.Context, next: *mizu.Next) anyerror!void {
    if (ctx.header("x-api-key") == null) {
        try ctx.status(.unauthorized);
        return;
    }

    try next.run();
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
const id = ctx.param("id");         // URL path parameter
const postId = ctx.param("post_id"); // Multiple params are supported
const value = ctx.query("key");      // Query string parameter
const body = try ctx.body();        // Request body
const header = ctx.header("Content-Type"); // Request header
```

## Middleware

```zig
// Server-level middleware (applies to all routes)
var api = server.group("/api");
api.use("*").middleware(logger).register();

// Route middleware using Builder pattern
server.get("/dashboard").middleware(auth).handle(dashboardHandler);
server.post("/posts").middleware(requireJson).handle(createPostHandler);

// Multiple middleware
server.post("/posts")
    .middleware(auth)
    .middleware(rateLimit)
    .middleware(requireJson)
    .handle(createPostHandler);
```

Middleware signatures use `*mizu.Next`:

```zig
fn authMiddleware(ctx: *mizu.Context, next: *mizu.Next) anyerror!void {
    if (ctx.header("authorization") == null) {
        try ctx.status(.unauthorized);
        return;
    }

    try next.run();
}
```

## Routing

```zig
// Static routes
server.get("/", handler);
server.post("/submit", handler);

// Path parameters (prefixed with :)
server.get("/users/:id", handler);
server.get("/articles/:year/:month", handler);

// Route groups
var api = server.group("/api");
api.get("/users", handler); // /api/users
api.use("*").middleware(authMiddleware); // applies to /api/*

var v1 = server.group("/v1");
var posts = v1.group("/posts");
posts.get("/:id", handler); // /v1/posts/:id
```

## Error Handling

```zig
// Server-level error handler
// Return void (no error) to stop propagation
// Return error to propagate to parent
try server.onErr(serverErrHandler);

fn serverErrHandler(ctx: *mizu.Context, err: anyerror) anyerror!void {
    try ctx.status(.internal_server_error);
}

// Group-level error handler
var api = server.group("/api");
try api.onErr(apiErrHandler);

fn apiErrHandler(_: *mizu.Context, _: anyerror) anyerror!void {
    // Handle error, don't return error to stop propagation
}
```

- Handler returns `void`: error stays at current layer, not propagated to parent
- Handler returns `error`: error propagates to parent group or server
- Multiple handlers execute in registration order, first registered runs first

## Supported HTTP Methods

- `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, `HEAD`

## TODO

- Buffer responses so middleware can safely adjust status codes and headers after `try next.run()`.

## Requirements

- Zig 0.16.0 or later