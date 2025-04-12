const std = @import("std");
const Event = @import("../events/event.zig").Event;
const BaseAgent = @import("base_agent.zig").BaseAgent;
const InvocationContext = @import("invocation_context.zig").InvocationContext;

/// Parallel agent implementation.
/// A shell agent that runs its sub-agents in parallel in isolated manner.
///
/// This approach is beneficial for scenarios requiring multiple perspectives or
/// attempts on a single task, such as:
///
/// - Running different algorithms simultaneously.
/// - Generating multiple responses for review by a subsequent evaluation agent.
pub const ParallelAgent = struct {
    base: BaseAgent,

    /// Run the agent asynchronously
    pub fn runAsyncImpl(self: *BaseAgent, ctx: *InvocationContext) !std.ArrayList(Event) {
        const parallel_agent = @as(*ParallelAgent, @ptrCast(self));
        var events = std.ArrayList(Event).init(std.heap.page_allocator);

        // Set branch for current agent
        if (ctx.branch.len > 0) {
            ctx.branch = try std.fmt.allocPrint(
                std.heap.page_allocator,
                "{s}.{s}",
                .{ ctx.branch, parallel_agent.base.name },
            );
        } else {
            ctx.branch = try std.heap.page_allocator.dupe(u8, parallel_agent.base.name);
        }

        // Run all sub-agents and collect their events
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
        _ = self;
        _ = ctx;
        return error.NotImplemented;
    }
};
