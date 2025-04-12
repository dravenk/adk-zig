const std = @import("std");

/// Enum for different streaming modes
pub const StreamingMode = enum {
    none,
    sse,
    bidi,
};

/// Speech configuration type (placeholder)
pub const SpeechConfig = struct {};

/// Audio transcription configuration type (placeholder)
pub const AudioTranscriptionConfig = struct {};

/// Configs for runtime behavior of agents
pub const RunConfig = struct {
    /// Speech configuration for the live agent
    speech_config: ?SpeechConfig = null,

    /// The output modalities. If not set, it's default to AUDIO
    response_modalities: ?std.ArrayList([]const u8) = null,

    /// Whether or not to save the input blobs as artifacts
    save_input_blobs_as_artifacts: bool = false,

    /// Whether to support CFC (Compositional Function Calling). Only applicable for
    /// StreamingMode.sse. If it's true, the LIVE API will be invoked. Since only LIVE
    /// API supports CFC
    ///
    /// Warning: This feature is experimental and its API or behavior may change
    /// in future releases.
    support_cfc: bool = false,

    /// Streaming mode
    streaming_mode: StreamingMode = .none,

    /// Output transcription for live agents with audio response
    output_audio_transcription: ?AudioTranscriptionConfig = null,

    /// A limit on the total number of llm calls for a given run.
    ///
    /// Valid Values:
    /// - More than 0: The bound on the number of llm calls is enforced.
    /// - Less than or equal to 0: This allows for unbounded number of llm calls.
    max_llm_calls: i32 = 500,

    /// Validate max_llm_calls
    pub fn validateMaxLlmCalls(self: *RunConfig) !void {
        if (self.max_llm_calls == std.math.maxInt(i32)) {
            return error.InvalidMaxLlmCalls;
        } else if (self.max_llm_calls <= 0) {
            std.log.warn(
                "max_llm_calls is less than or equal to 0. This will result in " ++
                    "no enforcement on total number of llm calls that will be made for a " ++
                    "run. This may not be ideal, as this could result in a never " ++
                    "ending communication between the model and the agent in certain cases.",
                .{},
            );
        }
    }
};
