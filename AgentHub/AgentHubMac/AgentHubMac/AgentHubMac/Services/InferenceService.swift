import Foundation
import AgentKit

/// On-device model inference (Llama for chat/planning, Whisper for
/// transcription). Mac-only — the weights are large `.gguf` files in
/// Resources/Models and never sync to the iPhone. This is a primary reason the
/// Mac remains the executor even though Composio is hosted.
actor InferenceService {
    struct Completion: Sendable {
        var text: String
    }

    /// Generate the next model turn given the running transcript. Returns text
    /// that `AgentRunner` parses for tool calls.
    func complete(prompt: String, model: LocalModel) async throws -> Completion {
        // TODO: load the .gguf weights and run llama.cpp / MLX inference.
        Completion(text: "")
    }

    func transcribe(audioURL: URL, model: LocalModel) async throws -> String {
        // TODO: Whisper inference.
        ""
    }
}
