import Foundation

/// One event from the agent-harness ReAct loop, as streamed by `server.py`'s
/// `POST /chat` SSE endpoint. Shapes mirror `core/loop.py`'s `run()` docstring
/// exactly — see `agent-harness/docs/Understanding/loop_events_for_a_frontend.md`
/// for the full contract. JSON field names are the only thing shared with the
/// Python side.
public enum HarnessEvent: Sendable {
    /// One full trip through the loop: one model call plus any tools it
    /// requested. NOT one turn per tool call.
    case turnStart(turn: Int)
    /// The model is generating; nothing observable yet. Show a spinner until
    /// the next event.
    case thinkingStatus
    /// A specific tool is about to be dispatched.
    case toolRunning(name: String)
    /// Text the model said *alongside* a tool-call request.
    case thinking(text: String)
    case toolCall(id: String, name: String, arguments: String)
    case toolResult(toolCallID: String, name: String, result: String)
    /// The model's final answer for this user turn.
    case final(text: String)
    /// The loop hit max turns without producing a final answer.
    case maxTurns
    /// The run failed server-side (e.g. the inference server is down).
    /// Emitted by server.py's wrapper, not the loop itself; the session's
    /// history is rolled back server-side, so the conversation stays usable.
    case error(message: String)
}

extension HarnessEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, turn, state, name, text, id, arguments, result, message
        case toolCallID = "tool_call_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "turn_start":
            self = .turnStart(turn: try container.decode(Int.self, forKey: .turn))
        case "status":
            let state = try container.decode(String.self, forKey: .state)
            if state == "tool_running" {
                self = .toolRunning(name: try container.decode(String.self, forKey: .name))
            } else {
                self = .thinkingStatus
            }
        case "thinking":
            self = .thinking(text: try container.decode(String.self, forKey: .text))
        case "tool_call":
            // Arguments arrive as an arbitrary JSON object; carry them as a
            // canonical JSON string rather than modeling every shape — compact
            // enough to display, and still parseable by consumers that inspect
            // arguments (e.g. AgentRunner detecting drafted replies).
            let arguments = try container.decodeIfPresent(JSONValue.self, forKey: .arguments)
            self = .toolCall(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                arguments: arguments?.jsonString ?? "{}"
            )
        case "tool_result":
            self = .toolResult(
                toolCallID: try container.decode(String.self, forKey: .toolCallID),
                name: try container.decode(String.self, forKey: .name),
                result: try container.decode(String.self, forKey: .result)
            )
        case "final":
            self = .final(text: try container.decode(String.self, forKey: .text))
        case "max_turns":
            self = .maxTurns
        case "error":
            self = .error(message: try container.decode(String.self, forKey: .message))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown harness event type '\(type)'"
            )
        }
    }
}

/// Minimal arbitrary-JSON value, just enough to round-trip tool-call
/// arguments back into a canonical JSON string.
enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    private var foundationObject: Any {
        switch self {
        case .string(let s): s
        case .number(let n): n
        case .bool(let b): b
        case .null: NSNull()
        case .array(let items): items.map(\.foundationObject)
        case .object(let fields): fields.mapValues(\.foundationObject)
        }
    }

    /// Valid, compact, key-sorted JSON — string escaping included.
    var jsonString: String {
        let object = foundationObject
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
