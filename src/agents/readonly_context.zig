const std = @import("std");
const InvocationContext = @import("invocation_context.zig").InvocationContext;

/// ReadonlyContext provides a read-only view of the invocation context.
pub const ReadonlyContext = struct {
    /// The underlying invocation context.
    invocation_context: *InvocationContext,

    /// Initialize a new ReadonlyContext
    pub fn init(invocation_context: *InvocationContext) ReadonlyContext {
        return .{
            .invocation_context = invocation_context,
        };
    }

    /// The current invocation id.
    pub fn invocationId(self: *const ReadonlyContext) []const u8 {
        return self.invocation_context.invocation_id;
    }

    /// The name of the agent that is currently running.
    pub fn agentName(self: *const ReadonlyContext) []const u8 {
        return self.invocation_context.agent.name;
    }

    /// The state of the current session. READONLY field.
    pub fn state(self: *const ReadonlyContext) std.StringHashMap(std.json.Value) {
        return self.invocation_context.session.state;
    }
};
