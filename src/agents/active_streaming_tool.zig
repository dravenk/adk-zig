const std = @import("std");
const LiveRequestQueue = @import("live_request_queue.zig").LiveRequestQueue;

/// Manages streaming tool related resources during invocation.
pub const ActiveStreamingTool = struct {
    /// The active task of this streaming tool.
    task: ?*std.Thread = null,

    /// The active (input) streams of this streaming tool.
    stream: ?*LiveRequestQueue = null,

    pub fn init() ActiveStreamingTool {
        return ActiveStreamingTool{
            .task = null,
            .stream = null,
        };
    }
};
