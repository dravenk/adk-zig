const std = @import("std");
const uuid = @import("uuid");
const types = @import("google.genai.types");
const Content = types.Content;
const Part = types.Part;
const BaseArtifactService = @import("../artifacts/base_artifact_service.zig").BaseArtifactService;
const BaseMemoryService = @import("../memory/base_memory_service.zig").BaseMemoryService;
const BaseSessionService = @import("../sessions/base_session_service.zig").BaseSessionService;
const Session = @import("../sessions/session.zig").Session;
const ActiveStreamingTool = @import("active_streaming_tool.zig").ActiveStreamingTool;
const BaseAgent = @import("base_agent.zig").BaseAgent;
const LiveRequestQueue = @import("live_request_queue.zig").LiveRequestQueue;
const RunConfig = @import("run_config.zig").RunConfig;
const TranscriptionEntry = @import("transcription_entry.zig").TranscriptionEntry;

/// Error thrown when the number of LLM calls exceed the limit.
pub const LlmCallsLimitExceededError = error{
    LlmCallsLimitExceeded,
};

/// A container to keep track of the cost of invocation.
///
/// While we don't expected the metrics captured here to be a direct
/// representatative of monetary cost incurred in executing the current
/// invocation, but they, in someways have an indirect affect.
const InvocationCostManager = struct {
    number_of_llm_calls: usize = 0,
    /// A counter that keeps track of number of llm calls made.
    /// Increments number_of_llm_calls and enforces the limit.
    pub fn incrementAndEnforceLlmCallsLimit(
        self: *InvocationCostManager,
        run_config: ?*const RunConfig,
    ) !void {
        // We first increment the counter and then check the conditions.
        self.number_of_llm_calls += 1;

        if (run_config != null and
            run_config.?.max_llm_calls > 0 and
            self.number_of_llm_calls > run_config.?.max_llm_calls)
        {
            // We only enforce the limit if the limit is a positive number.
            return LlmCallsLimitExceededError.LlmCallsLimitExceeded;
        }
    }
};

/// An invocation context represents the data of a single invocation of an agent.
///
/// An invocation:
///   1. Starts with a user message and ends with a final response.
///   2. Can contain one or multiple agent calls.
///   3. Is handled by runner.runAsync().
///
/// An invocation runs an agent until it does not request to transfer to another
/// agent.
///
/// An agent call:
///   1. Is handled by agent.run().
///   2. Ends when agent.run() ends.
///
/// An LLM agent call is an agent with a BaseLLMFlow.
/// An LLM agent call can contain one or multiple steps.
///
/// An LLM agent runs steps in a loop until:
///   1. A final response is generated.
///   2. The agent transfers to another agent.
///   3. The end_invocation is set to true by any callbacks or tools.
///
/// A step:
///   1. Calls the LLM only once and yields its response.
///   2. Calls the tools and yields their responses if requested.
///
/// The summarization of the function response is considered another step, since
/// it is another llm call.
/// A step ends when it's done calling llm and tools, or if the end_invocation
/// is set to true at any time.
///
/// ```
///    ┌─────────────────────── invocation ──────────────────────────┐
///    ┌──────────── llm_agent_call_1 ────────────┐ ┌─ agent_call_2 ─┐
///    ┌──── step_1 ────────┐ ┌───── step_2 ──────┐
///    [call_llm] [call_tool] [call_llm] [transfer]
/// ```
pub const InvocationContext = struct {
    artifact_service: ?*BaseArtifactService = null,
    session_service: *BaseSessionService,
    memory_service: ?*BaseMemoryService = null,

    invocation_id: []const u8,
    /// The id of this invocation context. Readonly.
    branch: ?[]const u8 = null,
    /// The branch of the invocation context.
    ///
    /// The format is like agent_1.agent_2.agent_3, where agent_1 is the parent of
    /// agent_2, and agent_2 is the parent of agent_3.
    ///
    /// Branch is used when multiple sub-agents shouldn't see their peer agents'
    /// conversation history.
    agent: *BaseAgent,
    /// The current agent of this invocation context. Readonly.
    user_content: ?Content = null,
    /// The user content that started this invocation. Readonly.
    session: *Session,
    /// The current session of this invocation context. Readonly.
    end_invocation: bool = false,
    /// Whether to end this invocation.
    ///
    /// Set to True in callbacks or tools to terminate this invocation.
    live_request_queue: ?*LiveRequestQueue = null,
    /// The queue to receive live requests.
    active_streaming_tools: ?std.StringHashMap(ActiveStreamingTool) = null,
    /// The running streaming tools of this invocation.
    transcription_cache: ?std.ArrayList(TranscriptionEntry) = null,
    /// Caches necessary, data audio or contents, that are needed by transcription.
    run_config: ?*RunConfig = null,
    /// Configurations for live agents under this invocation.
    invocation_cost_manager: InvocationCostManager = InvocationCostManager{},
    /// A container to keep track of different kinds of costs incurred as a part
    /// of this invocation.
    /// Tracks number of llm calls made.
    ///
    /// Raises:
    ///   LlmCallsLimitExceededError: If number of llm calls made exceed the set
    ///     threshold.
    pub fn incrementLlmCallCount(self: *InvocationContext) !void {
        try self.invocation_cost_manager.incrementAndEnforceLlmCallsLimit(self.run_config);
    }

    /// Returns the app name from the session.
    pub fn getAppName(self: *const InvocationContext) []const u8 {
        return self.session.app_name;
    }

    /// Returns the user ID from the session.
    pub fn getUserId(self: *const InvocationContext) []const u8 {
        return self.session.user_id;
    }

    /// Creates a clone of this invocation context.
    pub fn clone(self: *const InvocationContext) *InvocationContext {
        const new_context = std.heap.page_allocator.create(InvocationContext) catch unreachable;
        new_context.* = .{
            .artifact_service = self.artifact_service,
            .session_service = self.session_service,
            .memory_service = self.memory_service,
            .invocation_id = self.invocation_id,
            .branch = self.branch,
            .agent = self.agent,
            .user_content = self.user_content,
            .session = self.session,
            .end_invocation = self.end_invocation,
            .live_request_queue = self.live_request_queue,
            .active_streaming_tools = self.active_streaming_tools,
            .transcription_cache = self.transcription_cache,
            .run_config = self.run_config,
            .invocation_cost_manager = self.invocation_cost_manager,
        };
        return new_context;
    }
};

/// Generates a new invocation context ID.
pub fn newInvocationContextId() []const u8 {
    const id = uuid.uuid4();
    const id_str = std.fmt.allocPrint(std.heap.page_allocator, "e-{s}", .{id}) catch unreachable;
    return id_str;
}
