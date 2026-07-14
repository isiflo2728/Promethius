import Foundation
import SwiftData

/// A curated, user-facing result an agent produced — the kind of thing that
/// fills the "Recent insights" section of the Glance view (e.g. a meeting
/// summary with action items, a weekly digest). Distinct from `RunLogEntry`,
/// which is the granular replay timeline of a single run; an `Insight` is one
/// finished outcome the user actually reads.
///
/// CloudKit note: for the schema to sync, every stored property must have a
/// default value (or be optional) and every relationship must be optional.
@Model
public final class Insight {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    /// Headline shown on the card, e.g. "Design Sync — summary".
    public var title: String = ""
    /// Where it came from, shown as "via <source>", e.g. "Meeting Notes".
    public var source: String = ""
    /// SF Symbol name for the card's icon tile.
    public var iconName: String = "sparkles"
    public var kindRaw: String = InsightKind.summary.rawValue
    /// The prose body of the insight.
    public var detail: String = ""
    /// Action items / key points, stored newline-joined because SwiftData
    /// (and CloudKit) don't persist `[String]` directly.
    public var bulletsRaw: String = ""

    public var agent: Agent?

    public var kind: InsightKind {
        get { InsightKind(rawValue: kindRaw) ?? .summary }
        set { kindRaw = newValue.rawValue }
    }

    /// Bullet points, split from / joined into the persisted `bulletsRaw`.
    /// Blank lines are dropped so a trailing newline never yields an empty row.
    public var bullets: [String] {
        get {
            bulletsRaw
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
        }
        set { bulletsRaw = newValue.joined(separator: "\n") }
    }

    public init(
        title: String,
        source: String = "",
        kind: InsightKind = .summary,
        iconName: String = "sparkles",
        detail: String = "",
        bullets: [String] = []
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.title = title
        self.source = source
        self.kindRaw = kind.rawValue
        self.iconName = iconName
        self.detail = detail
        self.bulletsRaw = bullets.joined(separator: "\n")
    }
}

public enum InsightKind: String, Codable, CaseIterable, Sendable {
    /// A distilled write-up, usually with bullet action items.
    case summary
    /// A recurring digest, e.g. "This week".
    case digest
    /// A single notable finding or heads-up.
    case note
}
