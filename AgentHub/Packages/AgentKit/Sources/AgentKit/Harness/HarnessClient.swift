import Foundation

/// HTTP client for the agent-harness backend (`agent-harness/server.py`).
///
/// `POST /chat` returns Server-Sent Events; each `data:` line is one JSON
/// `HarnessEvent`. The server keeps per-`sessionID` conversation history in
/// memory, so the caller just reuses the same ID for every message in a
/// conversation — there is no other handshake.
public struct HarnessClient: Sendable {
    public let baseURL: URL

    public init(baseURL: URL = URL(string: "http://localhost:8000")!) {
        self.baseURL = baseURL
    }

    public enum Error: Swift.Error, LocalizedError {
        /// Connection refused / host down — the Python server isn't running.
        case serverUnreachable(underlying: Swift.Error)
        case badStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .serverUnreachable:
                "Can't reach the agent backend. Start it with `uv run uvicorn server:app` in agent-harness/."
            case .badStatus(let code):
                "The agent backend answered with HTTP \(code)."
            }
        }
    }

    /// Send one user message and stream back the loop's events as they happen.
    ///
    /// The stream finishes after `.final` or `.maxTurns` on a healthy run. The
    /// backend emits no error event — if it fails mid-run the stream just ends
    /// early, so callers must treat "ended without `.final`/`.maxTurns`" as a
    /// failure rather than waiting forever.
    public func chat(sessionID: String, message: String) -> AsyncThrowingStream<HarnessEvent, Swift.Error> {
        let request = makeChatRequest(sessionID: sessionID, message: message)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw Error.badStatus(http.statusCode)
                    }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = Data(line.dropFirst("data: ".count).utf8)
                        continuation.yield(try decoder.decode(HarnessEvent.self, from: payload))
                    }
                    continuation.finish()
                } catch let error as URLError where error.code == .cannotConnectToHost {
                    continuation.finish(throwing: Error.serverUnreachable(underlying: error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Ask the backend to survey every connected source and return the
    /// structured "On your plate" briefing. Plain JSON, not SSE — one slow
    /// round trip (the agent may spend minutes in tool calls) then the
    /// finished list.
    public func briefing() async throws -> HarnessBriefing {
        var request = URLRequest(url: baseURL.appending(path: "briefing"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw Error.badStatus(http.statusCode)
            }
            return try JSONDecoder().decode(HarnessBriefing.self, from: data)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw Error.serverUnreachable(underlying: error)
        }
    }

    private func makeChatRequest(sessionID: String, message: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            ["session_id": sessionID, "message": message]
        )
        // The loop can spend minutes inside model calls with nothing on the
        // wire; the default 60s per-byte timeout would kill healthy runs.
        request.timeoutInterval = 600
        return request
    }
}
