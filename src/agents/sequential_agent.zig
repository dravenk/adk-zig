const std = @import("std");
const Event = @import("../events/event.zig").Event;
const BaseAgent = @import("base_agent.zig").BaseAgent;
const InvocationContext = @import("invocation_context.zig").InvocationContext;

/// Sequential agent implementation.
/// A shell agent that runs its sub-agents in sequence.
pub const SequentialAgent = struct {
    base: BaseAgent,

    /// Run the agent asynchronously
    pub fn runAsyncImpl(self: *BaseAgent, ctx: *InvocationContext) !std.ArrayList(Event) {
        var events = std.ArrayList(Event).init(std.heap.page_allocator);

        for (self.sub_agents.items) |sub_agent| {
            const sub_events = try sub_agent.runAsync(ctx);
            for (sub_events.items) |event| {
                try events.append(event);
            }
        }

        return events;
    }

    /// Run the agent in live mode
    pub fn runLiveImpl(self: *BaseAgent, ctx: *InvocationContext) !std.ArrayList(Event) {
        var events = std.ArrayList(Event).init(std.heap.page_allocator);

        for (self.sub_agents.items) |sub_agent| {
            const sub_events = try sub_agent.runLive(ctx);
            for (sub_events.items) |event| {
                try events.append(event);
            }
        }

        return events;
    }
};
