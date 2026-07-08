import Foundation
import AgentKit

/// Talks to the AgentHub **backend service** — a small FastAPI app (run by the
/// Python side) that owns the Composio API key and wraps Composio's SDK. The
/// app never calls Composio directly and never sees the key; it only knows this
/// service's base URL (e.g. `http://localhost:8000` in dev).
///
/// Plug-and-play: once the service is running, point `Configuration.baseURL` at
/// it — the request/response shapes below already match its contract:
///
///   POST /connections                    → { connect_url, connection_id }
///   GET  /connections/{provider}/status  → { status, connection_id, account_label }
///   POST /actions/execute                → raw action-result JSON
///   GET  /tools?provider=gmail           → [ { slug, display_name } ]
///
/// Policy still lives in Swift: the "sending email needs approval" guardrail is
/// enforced by `RemoteToolCatalog` / `PendingApproval` *before* `executeAction`
/// is ever called. This client only executes — it does not decide.
actor ComposioClient {
    struct Configuration {
        /// Base URL of the backend service — NOT Composio. e.g.
        /// `URL(string: "http://localhost:8000")!` during development.
        var baseURL: URL
    }

    private let configuration: Configuration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session

        // The service speaks snake_case JSON; keep Swift types camelCase.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Connections

    /// `POST /connections` — start an OAuth connect flow for `provider`.
    /// Returns the Composio-hosted connect URL to open in the browser plus the
    /// connection id to poll and persist.
    func initiateConnection(_ provider: PermissionScope) async throws -> ConnectResponse {
        try await post("connections", body: ConnectRequest(provider: provider.composioProvider))
    }

    /// `GET /connections/{provider}/status` — has the user finished connecting?
    func connectionStatus(_ provider: PermissionScope) async throws -> ConnectionStatusResponse {
        try await get("connections/\(provider.composioProvider)/status")
    }

    // MARK: - Actions

    /// `POST /actions/execute` — run an action such as `GMAIL_CREATE_EMAIL_DRAFT`
    /// against a specific connected account. Returns the raw JSON the service
    /// relays back from Composio.
    ///
    /// - Important: approval-gated actions (see `RemoteToolCatalog`) must already
    ///   have been resolved via `PendingApproval` before reaching here.
    func executeAction(
        slug: String,
        connectionId: String,
        arguments: [String: Any]
    ) async throws -> Data {
        var request = URLRequest(url: endpoint("actions/execute"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Built by hand because `arguments` is arbitrary JSON, not a fixed type.
        let body: [String: Any] = [
            "slug": slug,
            "connection_id": connectionId,
            "arguments": arguments,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            return try await send(request)
        } catch {
            throw ComposioError.executionFailed(slug: slug)
        }
    }

    // MARK: - Tools

    /// `GET /tools?provider=gmail` — list the real Composio action slugs the
    /// service exposes for a provider.
    func listTools(for provider: PermissionScope) async throws -> [RemoteTool] {
        try await get("tools", query: [URLQueryItem(name: "provider", value: provider.composioProvider)])
    }

    // MARK: - HTTP plumbing

    private func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)!
        components.path = (components.path as NSString).appendingPathComponent(path)
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        var request = URLRequest(url: endpoint(path, query: query))
        request.httpMethod = "GET"
        let data = try await send(request)
        return try decoder.decode(Response.self, from: data)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let data = try await send(request)
        return try decoder.decode(Response.self, from: data)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ComposioError.requestFailed(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}

// MARK: - Wire types (match the service's JSON)

/// Body of `POST /connections`.
struct ConnectRequest: Encodable {
    let provider: String
}

/// Response of `POST /connections`.
struct ConnectResponse: Decodable {
    /// Composio-hosted URL to open in `ASWebAuthenticationSession`.
    let connectUrl: URL
    /// Opaque id naming this connection; store it on `ConnectedAccount`.
    let connectionId: String
}

/// Response of `GET /connections/{provider}/status`.
struct ConnectionStatusResponse: Decodable {
    /// Raw status string; map via `ConnectionStatus(rawValue:)`.
    let status: String
    let connectionId: String?
    let accountLabel: String?

    var connectionStatus: ConnectionStatus {
        ConnectionStatus(rawValue: status) ?? .connecting
    }
}

/// One entry of `GET /tools`.
struct RemoteTool: Decodable {
    let slug: String
    let displayName: String
}

// MARK: - Provider mapping

extension PermissionScope {
    /// The lowercase provider slug the backend service expects in URLs and
    /// bodies (`gmail`, `slack`, ...). Only meaningful for remote scopes.
    var composioProvider: String {
        switch self {
        case .composioGmail:  return "gmail"
        case .composioSlack:  return "slack"
        case .composioNotion: return "notion"
        case .composioGitHub: return "github"
        default:              return rawValue
        }
    }
}

enum ComposioError: Error {
    /// A non-2xx response from the backend service.
    case requestFailed(status: Int)
    /// `executeAction` failed for a specific action slug.
    case executionFailed(slug: String)
    /// The provider isn't connected yet — kick off `ConnectionManager.connect`.
    case notConnected(provider: PermissionScope)
}
