import Foundation
import AuthenticationServices

/// The small survivor of the old `OAuth/` folder. Under Composio we no longer
/// implement provider OAuth ourselves or store tokens — Composio does both.
/// All this does is open Composio's connect URL in a secure web session and
/// hand back the callback so `ConnectionManager` can finalize the connection.
@MainActor
final class ConnectionCoordinator: NSObject {
    /// Opens `url` (a Composio-generated connect link) and resolves with the
    /// callback URL once the provider redirects back.
    func authenticate(url: URL, callbackScheme: String = "agenthub") async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? ConnectionError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.start()
        }
    }
}

extension ConnectionCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

enum ConnectionError: Error {
    case cancelled
}
