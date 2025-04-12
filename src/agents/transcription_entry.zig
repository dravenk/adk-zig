const std = @import("std");

/// Store the data that can be used for transcription.
pub const TranscriptionEntry = struct {
    /// The role that created this data, typically "user" or "model"
    role: []const u8,

    /// The data that can be used for transcription
    data: union(enum) {
        Blob: []const u8,
        Content: []const u8,
    },

    pub fn init(role: []const u8, data: anytype) !TranscriptionEntry {
        return TranscriptionEntry{
            .role = role,
            .data = switch (@TypeOf(data)) {
                // Assuming Blob and Content are string-like types in this context
                // Adjust these types based on the actual requirements
                []const u8 => .{ .Blob = data },
                else => .{ .Content = try std.fmt.allocPrint(std.heap.page_allocator, "{any}", .{data}) },
            },
        };
    }
};
