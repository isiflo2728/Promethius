import Foundation

/// The structured to-do briefing `POST /briefing` returns: the agent's read
/// of everything connected (email, GitHub, Slack, …) distilled into the
/// things that actually need the user. Backs Today's "On your plate" section.
public struct HarnessBriefing: Codable, Sendable {
    /// False when the backend has no tool sources connected — the UI should
    /// prompt to connect accounts rather than show an empty plate as "done".
    public let connected: Bool
    /// One personal sentence summing up the plate ("A light week — two PRs
    /// and one email need you."). Empty when not connected.
    public let headline: String
    public let items: [Item]

    public struct Item: Codable, Sendable, Identifiable {
        public enum Urgency: String, Codable, Sendable {
            case now
            case today
            case thisWeek = "this_week"
        }

        public let id = UUID()
        public let title: String
        /// Which source it came from: "gmail", "github", "slack", "calendar",
        /// or whatever tool name the agent reported.
        public let source: String
        public let detail: String
        public let urgency: Urgency

        private enum CodingKeys: String, CodingKey {
            case title, source, detail, urgency
        }

        // Manual decode: `title` is the only field the item is useless
        // without; everything else degrades gracefully when a local model
        // omits or garbles it.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            source = (try? container.decode(String.self, forKey: .source)) ?? ""
            detail = (try? container.decode(String.self, forKey: .detail)) ?? ""
            urgency = (try? container.decode(Urgency.self, forKey: .urgency)) ?? .today
        }

        public init(title: String, source: String = "", detail: String = "", urgency: Urgency = .today) {
            self.title = title
            self.source = source
            self.detail = detail
            self.urgency = urgency
        }
    }

    public init(connected: Bool, headline: String, items: [Item]) {
        self.connected = connected
        self.headline = headline
        self.items = items
    }
}
