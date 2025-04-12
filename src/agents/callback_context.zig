const std = @import("std");
const ReadonlyContext = @import("readonly_context.zig").ReadonlyContext;
const EventActions = @import("../events/event_actions.zig").EventActions;
const State = @import("../sessions/state.zig").State;
const InvocationContext = @import("invocation_context.zig").InvocationContext;
const Part = @import("google.genai.types").Part;
const Content = @import("google.genai.types").Content;

/// The context of various callbacks within an agent run.
pub const CallbackContext = struct {
    readonly_context: ReadonlyContext,
    event_actions: *EventActions,
    state: *State,

    /// Initialize a new CallbackContext
    pub fn init(
        invocation_context: *InvocationContext,
        event_actions: ?*EventActions,
    ) !*CallbackContext {
        const context = try std.heap.page_allocator.create(CallbackContext);

        context.readonly_context = ReadonlyContext.init(invocation_context);

        // Use provided event_actions or create a new one
        if (event_actions) |actions| {
            context.event_actions = actions;
        } else {
            const new_actions = try std.heap.page_allocator.create(EventActions);
            new_actions.* = EventActions.init();
            context.event_actions = new_actions;
        }

        // Create state with delta awareness
        const new_state = try std.heap.page_allocator.create(State);
        new_state.* = State.init(
            invocation_context.session.state,
            context.event_actions.state_delta,
        );
        context.state = new_state;

        return context;
    }

    /// The user content that started this invocation. READONLY field.
    pub fn getUserContent(self: *const CallbackContext) ?Content {
        return self.readonly_context.invocation_context.user_content;
    }

    /// Loads an artifact attached to the current session.
    ///
    /// Args:
    ///   filename: The filename of the artifact.
    ///   version: The version of the artifact. If null, the latest version will be returned.
    ///
    /// Returns:
    ///   The artifact.
    pub fn loadArtifact(
        self: *CallbackContext,
        filename: []const u8,
        version: ?i32,
    ) !?Part {
        const invocation_context = self.readonly_context.invocation_context;

        if (invocation_context.artifact_service == null) {
            return error.ArtifactServiceNotInitialized;
        }

        return try invocation_context.artifact_service.?.loadArtifact(
            invocation_context.app_name,
            invocation_context.user_id,
            invocation_context.session.id,
            filename,
            version,
        );
    }

    /// Saves an artifact and records it as delta for the current session.
    ///
    /// Args:
    ///   filename: The filename of the artifact.
    ///   artifact: The artifact to save.
    ///
    /// Returns:
    ///   The version of the artifact.
    pub fn saveArtifact(
        self: *CallbackContext,
        filename: []const u8,
        artifact: Part,
    ) !i32 {
        const invocation_context = self.readonly_context.invocation_context;

        if (invocation_context.artifact_service == null) {
            return error.ArtifactServiceNotInitialized;
        }

        const version = try invocation_context.artifact_service.?.saveArtifact(
            invocation_context.app_name,
            invocation_context.user_id,
            invocation_context.session.id,
            filename,
            artifact,
        );

        try self.event_actions.artifact_delta.put(filename, version);
        return version;
    }
};
