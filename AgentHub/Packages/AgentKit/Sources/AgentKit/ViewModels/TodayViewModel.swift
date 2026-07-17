import Foundation
import Observation

/// Source of real calendar events for the Today view's "What's next" section.
/// The Mac app implements this over EventKit; the package only knows the
/// shape, so view models stay testable without a calendar store.
@MainActor
public protocol UpcomingEventProviding {
    /// Fetch the next `limit` events, requesting calendar access if needed.
    /// Never returns `.loading` or `.noProvider` — those are view-model states.
    func upcomingEvents(limit: Int) async -> CalendarState
}

/// What the "What's next" section should show.
public enum CalendarState: Sendable {
    /// Fetch in flight (or not started yet).
    case loading
    /// No `UpcomingEventProviding` was injected (previews, tests).
    case noProvider
    /// The user declined calendar access.
    case accessDenied
    /// Real events, soonest first. Empty means a clear week.
    case events([UpcomingEvent])
}

/// What the "On your plate" section should show.
public enum PlateState: Sendable {
    /// The agent is out surveying the connected sources.
    case loading
    /// The backend has no tool sources connected yet.
    case noSources
    /// The briefing couldn't be built — message explains why.
    case unavailable(String)
    /// The finished briefing.
    case briefing(HarnessBriefing)
}

/// Backs the "Today" home tab: a greeting with live counts, the things that
/// need the user ("Needs you" — pending approvals + stalled agents), the
/// agent-built "On your plate" briefing, and a weekly summary with what's
/// next on the calendar.
@MainActor
@Observable
public final class TodayViewModel {
    public private(set) var runningAgents: [Agent] = []
    public private(set) var stalledAgents: [Agent] = []
    public private(set) var pendingApprovals: [PendingApproval] = []
    public private(set) var recentActivity: [RunLogEntry] = []
    public private(set) var weeklySummary: String = ""
    public private(set) var calendarState: CalendarState = .loading
    public private(set) var plateState: PlateState = .loading
    /// True while a fresh briefing is being built *behind* a stale one that's
    /// already on screen — drives the "Updating…" indicator, not a spinner
    /// that hides content.
    public private(set) var isRefreshingPlate = false
    public var errorMessage: String?

    private let repository: AgentRepository
    private let eventProvider: UpcomingEventProviding?
    private let harness: HarnessClient

    /// Briefings cost a full agent run over every connected source (minutes
    /// on a local model), so the user should never wait on one they've
    /// already paid for: the last briefing is cached in memory AND on disk
    /// (surviving app restarts), shown instantly, and refreshed in the
    /// background when stale. `inflightBriefing` dedupes concurrent fetches
    /// (app-launch warmup + opening Today) into one agent run.
    private struct CachedBriefing: Codable {
        let briefing: HarnessBriefing
        let fetchedAt: Date
    }

    private static var cachedBriefing: CachedBriefing?
    private static var inflightBriefing: Task<HarnessBriefing, Swift.Error>?
    private static let briefingMaxAge: TimeInterval = 30 * 60
    private static let briefingCacheKey = "today.briefing.cache"

    public init(
        repository: AgentRepository,
        eventProvider: UpcomingEventProviding? = nil,
        harness: HarnessClient = HarnessClient()
    ) {
        self.repository = repository
        self.eventProvider = eventProvider
        self.harness = harness
    }

    public func refresh() {
        do {
            let agents = try repository.allAgents()
            runningAgents = agents.filter { $0.status == .running }
            stalledAgents = agents.filter { $0.status == .failed }
            pendingApprovals = try repository.pendingApprovals()
            recentActivity = try repository.recentRunLog(limit: 8)
            weeklySummary = Self.summarize(
                try repository.runLog(since: Date(timeIntervalSinceNow: -7 * 24 * 3600)),
                pendingApprovalCount: pendingApprovals.count
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Show the "On your plate" briefing. Stale-while-revalidate: any cached
    /// briefing (memory or disk) appears instantly; if it's stale — or
    /// `force` was passed — a fresh agent run happens behind it and swaps in
    /// when done. The user only ever watches a spinner when there has never
    /// been a briefing to show.
    public func loadPlate(force: Bool = false) async {
        if let cached = Self.loadCachedBriefing() {
            plateState = .briefing(cached.briefing)
            if !force, Date().timeIntervalSince(cached.fetchedAt) < Self.briefingMaxAge {
                return
            }
            isRefreshingPlate = true
        } else {
            plateState = .loading
        }
        defer { isRefreshingPlate = false }

        do {
            let briefing = try await Self.sharedBriefingFetch(harness)
            plateState = briefing.connected ? .briefing(briefing) : .noSources
        } catch {
            // A failed background refresh keeps the stale briefing on screen;
            // only surface the error when there was nothing to show instead.
            if case .briefing = plateState { return }
            plateState = .unavailable(error.localizedDescription)
        }
    }

    /// Kick off a briefing run at app launch so it's (mostly) done before the
    /// user first looks at Today. No-op when the cache is still fresh; safe
    /// to race with `loadPlate` thanks to the shared in-flight task.
    public static func warmBriefing(harness: HarnessClient = HarnessClient()) async {
        if let cached = loadCachedBriefing(),
           Date().timeIntervalSince(cached.fetchedAt) < briefingMaxAge {
            return
        }
        _ = try? await sharedBriefingFetch(harness)
    }

    private static func loadCachedBriefing() -> CachedBriefing? {
        if let cachedBriefing { return cachedBriefing }
        guard let data = UserDefaults.standard.data(forKey: briefingCacheKey),
              let cached = try? JSONDecoder().decode(CachedBriefing.self, from: data) else {
            return nil
        }
        cachedBriefing = cached
        return cached
    }

    /// One agent run, no matter how many callers ask at once.
    private static func sharedBriefingFetch(_ harness: HarnessClient) async throws -> HarnessBriefing {
        if let inflightBriefing {
            return try await inflightBriefing.value
        }
        let task = Task { try await harness.briefing() }
        inflightBriefing = task
        defer { inflightBriefing = nil }

        let briefing = try await task.value
        if briefing.connected {
            let cached = CachedBriefing(briefing: briefing, fetchedAt: Date())
            cachedBriefing = cached
            if let data = try? JSONEncoder().encode(cached) {
                UserDefaults.standard.set(data, forKey: briefingCacheKey)
            }
        }
        return briefing
    }

    /// Fetch real calendar events for "What's next". Safe to call on every
    /// appearance — the provider only prompts for access once.
    public func loadCalendar() async {
        guard let eventProvider else {
            calendarState = .noProvider
            return
        }
        calendarState = await eventProvider.upcomingEvents(limit: 5)
    }

    /// Time-of-day greeting, e.g. "Good morning".
    public var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    public var runningCount: Int { runningAgents.count }

    /// Approvals plus stalled agents — everything in the "Needs you" section.
    public var needsYouCount: Int { pendingApprovals.count + stalledAgents.count }

    /// "2 agents working right now · 3 things need you."
    public var subtitle: String {
        let agents = "\(runningCount) agent\(runningCount == 1 ? "" : "s") working right now"
        let needs = "\(needsYouCount) thing\(needsYouCount == 1 ? "" : "s") need\(needsYouCount == 1 ? "s" : "") you"
        return "\(agents) · \(needs)."
    }

    /// The most recent error line for a stalled agent — the "why" shown on its
    /// card. Falls back to a generic message.
    public func reason(for agent: Agent) -> String {
        let errors = (agent.runLog ?? []).filter { $0.kind == .error }
        return errors.max { $0.timestamp < $1.timestamp }?.message
            ?? "Stopped unexpectedly and needs a nudge to continue."
    }

    /// Clear a stalled agent by handing it back to the runner.
    public func retry(_ agent: Agent) {
        try? repository.update(agent) { $0.status = .running }
        refresh()
    }

    // MARK: - This week

    /// Build the weekly recap from the last 7 days of real run-log entries.
    /// Static + pure so tests can feed it entries directly.
    static func summarize(_ entries: [RunLogEntry], pendingApprovalCount: Int) -> String {
        guard !entries.isEmpty else {
            return "No agent activity in the last 7 days. Kick off a run and this recap fills in."
        }

        let toolCalls = entries.filter { $0.kind == .toolCall }.count
        let errors = entries.filter { $0.kind == .error }.count
        let agentNames = Set(entries.compactMap { $0.agent?.name })

        var pieces: [String] = []
        if toolCalls > 0 {
            pieces.append("ran \(toolCalls) tool call\(toolCalls == 1 ? "" : "s")")
        }
        pieces.append("logged \(entries.count) event\(entries.count == 1 ? "" : "s")")
        if errors > 0 {
            pieces.append("hit \(errors) error\(errors == 1 ? "" : "s")")
        }

        let who = agentNames.count == 1
            ? (agentNames.first ?? "one agent")
            : "\(agentNames.count) agents"
        var summary = "This week \(who) \(pieces.formatted(.list(type: .and)))."
        if pendingApprovalCount > 0 {
            summary += " \(pendingApprovalCount) approval\(pendingApprovalCount == 1 ? " is" : "s are") still waiting on you."
        }
        return summary
    }
}

/// A single "What's next" row. Not persisted — a lightweight view value.
public struct UpcomingEvent: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let subtitle: String
    public let timeLabel: String

    public init(title: String, subtitle: String, timeLabel: String) {
        self.title = title
        self.subtitle = subtitle
        self.timeLabel = timeLabel
    }
}
