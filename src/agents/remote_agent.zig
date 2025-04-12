const std = @import("std");
const Event = @import("../events/event.zig").Event;
const BaseAgent = @import("base_agent.zig").BaseAgent;
const InvocationContext = @import("invocation_context.zig").InvocationContext;
const http = @import("std").http;

/// RemoteAgent implementation.
/// Experimental, do not use.
pub const RemoteAgent = struct {
    base: BaseAgent,

    /// URL to send requests to
    url: []const u8,

    /// Run the agent asynchronously
    pub fn runAsyncImpl(self: *BaseAgent, ctx: *InvocationContext) !std.ArrayList(Event) {
        const remote_agent = @as(*RemoteAgent, @ptrCast(self));
        var events = std.ArrayList(Event).init(std.heap.page_allocator);

        // Prepare data to send
        var data = std.json.Value{
            .Object = std.json.ObjectMap.init(std.heap.page_allocator),
        };
        try data.Object.put("invocation_id", std.json.Value{ .String = ctx.invocation_id });

        // TODO: Implement session serialization
        // This is a placeholder for ctx.session serialization
        const session_data = std.json.Value{
            .Object = std.json.ObjectMap.init(std.heap.page_allocator),
        };
        try data.Object.put("session", session_data);

        // Serialize data to JSON
        var json_string = std.ArrayList(u8).init(std.heap.page_allocator);
        try std.json.stringify(data, .{}, json_string.writer());

        // Make HTTP request
        var client = http.Client{ .allocator = std.heap.page_allocator };
        defer client.deinit();

        var headers = http.Headers{ .allocator = std.heap.page_allocator };
        defer headers.deinit();
        try headers.append("content-type", "application/json");

        const uri = try std.Uri.parse(remote_agent.url);
        var request = try client.request(.POST, uri, headers, .{});
        defer request.deinit();
        request.transfer_encoding = .{ .content_length = json_string.items.len };

        try request.start();
        try request.writeAll(json_string.items);
        try request.finish();

        const response = try request.wait();
        if (response.status != .ok) {
            return error.HttpRequestFailed;
        }

        // Parse response
        var response_buffer = std.ArrayList(u8).init(std.heap.page_allocator);
        try response.reader().readAllArrayList(&response_buffer, 1024 * 1024);

        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            std.heap.page_allocator,
            response_buffer.items,
            .{},
        );
        defer parsed.deinit();

        if (parsed.value == .Array) {
            for (parsed.value.Array.items) |_| {
                // TODO: Implement proper Event deserialization
                const event = Event{
                    .content = "",
                    .author = remote_agent.base.name,
                    .actions = null,
                };
                try events.append(event);
            }
        }

        return events;
    }

    /// Run the agent in live mode
    pub fn runLiveImpl(self: *BaseAgent, ctx: *InvocationContext) !std.ArrayList(Event) {
        _ = self;
        _ = ctx;
        return error.NotImplemented;
    }
};
