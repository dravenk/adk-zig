const std = @import("std");
const types = @import("google.genai.types");
const Content = types.Content;
const Part = types.Part;
const GenerateContentConfig = types.GenerateContentConfig;
const Event = @import("../events/event.zig").Event;
const BaseAgent = @import("base_agent.zig").BaseAgent;
const InvocationContext = @import("invocation_context.zig").InvocationContext;
const ReadonlyContext = @import("readonly_context.zig").ReadonlyContext;
const CallbackContext = @import("callback_context.zig").CallbackContext;
const ToolContext = @import("../tools/tool_context.zig").ToolContext;
const BaseTool = @import("../tools/base_tool.zig").BaseTool;
const FunctionTool = @import("../tools/function_tool.zig").FunctionTool;
const BaseLlm = @import("../models/base_llm.zig").BaseLlm;
const LlmRequest = @import("../models/llm_request.zig").LlmRequest;
const LlmResponse = @import("../models/llm_response.zig").LlmResponse;
const LLMRegistry = @import("../models/registry.zig").LLMRegistry;
const BaseLlmFlow = @import("../flows/llm_flows/base_llm_flow.zig").BaseLlmFlow;
const SingleFlow = @import("../flows/llm_flows/single_flow.zig").SingleFlow;
const AutoFlow = @import("../flows/llm_flows/auto_flow.zig").AutoFlow;
const BaseCodeExecutor = @import("../code_executors/base_code_executor.zig").BaseCodeExecutor;
const BasePlanner = @import("../planners/base_planner.zig").BasePlanner;
const BaseExampleProvider = @import("../examples/base_example_provider.zig").BaseExampleProvider;
const Example = @import("../examples/example.zig").Example;

const logger = std.log.scoped(.llm_agent);

/// Callback type for before model execution
pub const BeforeModelCallback = fn (
    context: *CallbackContext,
    request: *LlmRequest,
) ?*LlmResponse;

/// Callback type for after model execution
pub const AfterModelCallback = fn (
    context: *CallbackContext,
    response: *LlmResponse,
) ?*LlmResponse;

/// Callback type for before tool execution
pub const BeforeToolCallback = fn (
    tool: *BaseTool,
    args: std.StringHashMap(std.json.Value),
    tool_context: *ToolContext,
) ?std.StringHashMap(std.json.Value);

/// Callback type for after tool execution
pub const AfterToolCallback = fn (
    tool: *BaseTool,
    args: std.StringHashMap(std.json.Value),
    tool_context: *ToolContext,
    response: std.StringHashMap(std.json.Value),
) ?std.StringHashMap(std.json.Value);

/// Function that provides instructions based on context
pub const InstructionProvider = fn (context: *ReadonlyContext) []const u8;

/// Union type for tools
pub const ToolUnion = union(enum) {
    function: fn () void,
    tool: *BaseTool,
};

/// Union type for examples
pub const ExamplesUnion = union(enum) {
    examples: []Example,
    provider: *BaseExampleProvider,
};

/// Convert a ToolUnion to a BaseTool
fn convertToolUnionToTool(tool_union: ToolUnion) *BaseTool {
    return switch (tool_union) {
        .tool => |tool| tool,
        .function => |func| FunctionTool.create(func),
    };
}

/// LLM-based Agent
pub const LlmAgent = struct {
    base: BaseAgent,

    /// The model to use for the agent.
    /// When not set, the agent will inherit the model from its ancestor.
    model: union(enum) {
        name: []const u8,
        instance: *BaseLlm,
    } = .{ .name = "" },

    /// Instructions for the LLM model, guiding the agent's behavior.
    instruction: union(enum) {
        text: []const u8,
        provider: InstructionProvider,
    } = .{ .text = "" },

    /// Instructions for all the agents in the entire agent tree.
    /// global_instruction ONLY takes effect in root agent.
    global_instruction: union(enum) {
        text: []const u8,
        provider: InstructionProvider,
    } = .{ .text = "" },

    /// Tools available to this agent.
    tools: std.ArrayList(ToolUnion),

    /// The additional content generation configurations.
    generate_content_config: ?GenerateContentConfig = null,

    /// Disallows LLM-controlled transferring to the parent agent.
    disallow_transfer_to_parent: bool = false,

    /// Disallows LLM-controlled transferring to the peer agents.
    disallow_transfer_to_peers: bool = false,

    /// Whether to include contents in the model request.
    include_contents: enum { default, none } = .default,

    /// The input schema when agent is used as a tool.
    input_schema: ?*anyopaque = null,

    /// The output schema when agent replies.
    output_schema: ?*anyopaque = null,

    /// The key in session state to store the output of the agent.
    output_key: ?[]const u8 = null,

    /// Instructs the agent to make a plan and execute it step by step.
    planner: ?*BasePlanner = null,

    /// Allow agent to execute code blocks from model responses.
    code_executor: ?*BaseCodeExecutor = null,

    /// Examples for the agent.
    examples: ?ExamplesUnion = null,

    /// Called before calling the LLM.
    before_model_callback: ?BeforeModelCallback = null,

    /// Called after calling LLM.
    after_model_callback: ?AfterModelCallback = null,

    /// Called before the tool is called.
    before_tool_callback: ?BeforeToolCallback = null,

    /// Called after the tool is called.
    after_tool_callback: ?AfterToolCallback = null,

    /// Initialize a new LlmAgent
    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*LlmAgent {
        const agent = try allocator.create(LlmAgent);
        agent.* = LlmAgent{
            .base = BaseAgent.init(name),
            .tools = std.ArrayList(ToolUnion).init(allocator),
        };
        return agent;
    }

    /// Run the agent asynchronously
    pub fn runAsyncImpl(self: *BaseAgent, ctx: *InvocationContext) !std.ArrayList(Event) {
        const llm_agent = @as(*LlmAgent, @ptrCast(self));
        var events = std.ArrayList(Event).init(std.heap.page_allocator);

        const flow = llm_agent.getLlmFlow();
        const flow_events = try flow.runAsync(ctx);

        for (flow_events.items) |event| {
            try llm_agent.maybeSaveOutputToState(&event);
            try events.append(event);
        }

        return events;
    }

    /// Run the agent in live mode
    pub fn runLiveImpl(self: *BaseAgent, ctx: *InvocationContext) !std.ArrayList(Event) {
        const llm_agent = @as(*LlmAgent, @ptrCast(self));
        var events = std.ArrayList(Event).init(std.heap.page_allocator);

        const flow = llm_agent.getLlmFlow();
        const flow_events = try flow.runLive(ctx);

        for (flow_events.items) |event| {
            try llm_agent.maybeSaveOutputToState(&event);
            try events.append(event);
        }

        if (ctx.end_invocation) {
            return events;
        }

        return events;
    }

    /// Get the canonical model
    pub fn getCanonicalModel(self: *LlmAgent) !*BaseLlm {
        return switch (self.model) {
            .instance => |model| model,
            .name => |name| {
                if (name.len > 0) {
                    return LLMRegistry.newLlm(name);
                } else {
                    // Find model from ancestors
                    var ancestor_agent = self.base.parent_agent;
                    while (ancestor_agent != null) {
                        if (@hasField(@TypeOf(ancestor_agent.?), "getCanonicalModel")) {
                            const llm_ancestor = @as(*LlmAgent, @ptrCast(ancestor_agent.?));
                            return llm_ancestor.getCanonicalModel();
                        }
                        ancestor_agent = ancestor_agent.?.parent_agent;
                    }
                    return error.NoModelFound;
                }
            },
        };
    }

    /// Get the canonical instruction
    pub fn getCanonicalInstruction(self: *LlmAgent, ctx: *ReadonlyContext) []const u8 {
        return switch (self.instruction) {
            .text => |text| text,
            .provider => |provider| provider(ctx),
        };
    }

    /// Get the canonical global instruction
    pub fn getCanonicalGlobalInstruction(self: *LlmAgent, ctx: *ReadonlyContext) []const u8 {
        return switch (self.global_instruction) {
            .text => |text| text,
            .provider => |provider| provider(ctx),
        };
    }

    /// Get the canonical tools
    pub fn getCanonicalTools(self: *LlmAgent) std.ArrayList(*BaseTool) {
        var result = std.ArrayList(*BaseTool).init(std.heap.page_allocator);
        for (self.tools.items) |tool| {
            result.append(convertToolUnionToTool(tool)) catch {};
        }
        return result;
    }

    /// Get the LLM flow for this agent
    fn getLlmFlow(self: *LlmAgent) *BaseLlmFlow {
        if (self.disallow_transfer_to_parent and
            self.disallow_transfer_to_peers and
            self.base.sub_agents.items.len == 0)
        {
            return SingleFlow.create();
        } else {
            return AutoFlow.create();
        }
    }

    /// Save the model output to state if needed
    fn maybeSaveOutputToState(self: *LlmAgent, event: *const Event) !void {
        if (self.output_key != null and
            event.isFinalResponse() and
            event.content != null and
            event.content.?.parts.len > 0)
        {
            var result = std.ArrayList(u8).init(std.heap.page_allocator);
            for (event.content.?.parts) |part| {
                if (part.text) |text| {
                    try result.appendSlice(text);
                }
            }

            if (self.output_schema != null) {
                // In Zig we would need to implement schema validation here
                // This is a simplified placeholder
                event.actions.state_delta.put(self.output_key.?, result.items) catch {};
            } else {
                event.actions.state_delta.put(self.output_key.?, result.items) catch {};
            }
        }
    }

    /// Validate the agent configuration
    pub fn validate(self: *LlmAgent) !void {
        try self.checkOutputSchema();
        try self.validateGenerateContentConfig();
    }

    /// Check output schema configuration
    fn checkOutputSchema(self: *LlmAgent) !void {
        if (self.output_schema == null) {
            return;
        }

        if (!self.disallow_transfer_to_parent or !self.disallow_transfer_to_peers) {
            logger.warn(
                "Invalid config for agent {s}: output_schema cannot co-exist with " ++
                    "agent transfer configurations. Setting " ++
                    "disallow_transfer_to_parent=true, disallow_transfer_to_peers=true",
                .{self.base.name},
            );
            self.disallow_transfer_to_parent = true;
            self.disallow_transfer_to_peers = true;
        }

        if (self.base.sub_agents.items.len > 0) {
            return error.InvalidConfig;
        }

        if (self.tools.items.len > 0) {
            return error.InvalidConfig;
        }
    }

    /// Validate generate content config
    fn validateGenerateContentConfig(self: *LlmAgent) !void {
        if (self.generate_content_config == null) {
            return;
        }

        const config = self.generate_content_config.?;

        if (config.thinking_config != null) {
            return error.InvalidConfig;
        }

        if (config.tools != null and config.tools.?.len > 0) {
            return error.InvalidConfig;
        }

        if (config.system_instruction != null) {
            return error.InvalidConfig;
        }

        if (config.response_schema != null) {
            return error.InvalidConfig;
        }
    }
};

/// Alias for LlmAgent
pub const Agent = LlmAgent;
