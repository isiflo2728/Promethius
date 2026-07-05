import Foundation
import AgentKit
// import MCP  // Composio exposes an MCP server; this client can ride on the
//               swift-sdk HTTPClientTransport you already scaffolded in
//               Promethius/TesMCP.swift. Swap the REST stubs below for MCP
//               tool calls once the transport is wired.

/// Talks to Composio — the hosted service that owns OAuth tokens and executes
/// third-party SaaS actions (Gmail, Slack, Notion, GitHub, ...).
///
/// There is no official Composio *Swift* SDK, so this client hits Composio's
/// REST API (or its MCP endpoint). The Composio API key lives ONLY here, on
/// the Mac, read from the Keychain — never bundled and never on the iPhone.
actor ComposioClient {
    struct Configuration {
        var baseURL: URL
        var apiKey: String
        /// Composio's notion of "which user" — usually one entity per install.
        var entityID: String
    }

    private let configuration: Configuration
    private let session: URLSession

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Execute a remote action, e.g. `GMAIL_CREATE_EMAIL_DRAFT`, against a
    /// specific connected account.
    ///
    /// - Note: action slugs and payload shapes come from Composio's catalog;
    ///   confirm exact names via `RemoteToolCatalog` before relying on them.
    func executeAction(
        slug: String,
        connectionId: String,
        arguments: [String: Any]
    ) async throws -> Data {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/actions/\(slug)/execute"))
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "connectedAccountId": connectionId,
            "entityId": configuration.entityID,
            "input": arguments,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ComposioError.executionFailed(slug: slug)
        }
        return data
    }
}

enum ComposioError: Error {
    case executionFailed(slug: String)
    case notConnected(provider: PermissionScope)
    case missingAPIKey
}
