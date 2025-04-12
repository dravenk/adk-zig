const std = @import("std");
const types = @import("google.genai.types");
const Content = types.Content;
const Blob = types.Blob;

/// Request sent to live agents.
pub const LiveRequest = struct {
    /// If set, send the content to the model in turn-by-turn mode.
    content: ?Content = null,

    /// If set, send the blob to the model in realtime mode.
    blob: ?Blob = null,

    /// If set, close the queue.
    close: bool = false,
};

/// Queue used to send LiveRequest in a live(bidirectional streaming) way.
pub const LiveRequestQueue = struct {
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    queue: std.ArrayList(LiveRequest),
    closed: bool,

    /// Initialize a new LiveRequestQueue
    pub fn init(allocator: std.mem.Allocator) LiveRequestQueue {
        return .{
            .mutex = .{},
            .condition = .{},
            .queue = std.ArrayList(LiveRequest).init(allocator),
            .closed = false,
        };
    }

    /// Close the queue
    pub fn close(self: *LiveRequestQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.queue.append(LiveRequest{ .close = true }) catch {};
        self.closed = true;
        self.condition.signal();
    }

    /// Send content to the queue
    pub fn sendContent(self: *LiveRequestQueue, content: Content) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed) return error.QueueClosed;

        try self.queue.append(LiveRequest{ .content = content });
        self.condition.signal();
    }

    /// Send realtime blob to the queue
    pub fn sendRealtime(self: *LiveRequestQueue, blob: Blob) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed) return error.QueueClosed;

        try self.queue.append(LiveRequest{ .blob = blob });
        self.condition.signal();
    }

    /// Send a request to the queue
    pub fn send(self: *LiveRequestQueue, req: LiveRequest) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed) return error.QueueClosed;

        try self.queue.append(req);
        self.condition.signal();
    }

    /// Get a request from the queue
    pub fn get(self: *LiveRequestQueue) !LiveRequest {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.queue.items.len == 0) {
            if (self.closed) return error.QueueClosed;
            self.condition.wait(&self.mutex);
        }

        const req = self.queue.orderedRemove(0);
        return req;
    }

    /// Deinitialize the queue
    pub fn deinit(self: *LiveRequestQueue) void {
        self.queue.deinit();
    }
};
