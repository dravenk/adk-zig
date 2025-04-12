const std = @import("std");
const Event = @import("../events/event.zig").Event;
const BaseAgent = @import("base_agent.zig").BaseAgent;
const InvocationContext = @import("invocation_context.zig").InvocationContext;

/// Loop agent implementation.
/// A shell agent that runs its sub-agents in a loop.
///
/// When sub-agent generates an event with escalate or max_iterations are
/// reached, the loop agent will stop.
pub const LoopAgent = struct {
    base: BaseAgent,

    /// The maximum number of iterations to run the loop agent.
    ///
    /// If not set (null), the loop agent will run indefinitely until a sub-agent
    /// escalates.
    max_iterations: ?usize = null,

    /// Run the agent asynchronously
    pub fn runAsyncImpl(self: *BaseAgent, ctx: *InvocationContext) !std.ArrayList(Event) {
        const loop_agent = @as(*LoopAgent, @ptrCast(self));
        var events = std.ArrayList(Event).init(std.heap.page_allocator);

        var times_looped: usize = 0;
        while (loop_agent.max_iterations == null or times_looped < loop_agent.max_iterations.?) {
            for (self.sub_agents.items) |sub_agent| {
                const sub_events = try sub_agent.runAsync(ctx);
                for (sub_events.items) |event| {
                    try events.append(event);
                    if (event.actions != null and event.actions.?.escalate) {
                        return events;
                    }
                }
            }
            times_looped += 1;
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
