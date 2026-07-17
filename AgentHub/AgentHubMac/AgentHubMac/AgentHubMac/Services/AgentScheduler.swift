import Foundation
import SwiftData
import AgentKit

/// Fires scheduled agent runs while the app is open. `Trigger` rows with
/// `kind == .schedule` have existed since the schema was written, but nothing
/// ever observed them — this is the observer. RootView ticks it once a minute.
///
/// Runs only happen while the app is running: this is a foreground app, not a
/// daemon. A schedule whose time passed while the app was closed fires on the
/// next tick after launch (see `Schedule.isDue`), so a "daily 09:00" agent
/// still runs when the Mac wakes at 9:30.
@MainActor
final class AgentScheduler {
    private let repository: AgentRepository
    private let runner: AgentRunner

    init(context: ModelContext) {
        let repository = AgentRepository(context: context)
        self.repository = repository
        self.runner = AgentRunner(repository: repository)
    }

    /// Start any agent whose enabled schedule trigger is due. Skips agents
    /// already running (the runner also guards this).
    func tick(now: Date = .now) {
        guard let agents = try? repository.allAgents() else { return }

        for agent in agents where agent.status != .running {
            guard
                let trigger = (agent.triggers ?? [])
                    .first(where: { $0.kind == .schedule && $0.isEnabled }),
                let schedule = Schedule(trigger.configuration)
            else { continue }

            let lastRunStart = (agent.runLog ?? [])
                .filter { $0.kind == .system && $0.message == "Run started" }
                .map(\.timestamp)
                .max()

            if schedule.isDue(now: now, lastRunStart: lastRunStart) {
                Task { await runner.run(agent) }
            }
        }
    }
}

/// The schedule strings the Schedule sheet writes into
/// `Trigger.configuration` — human-readable *and* parseable:
/// `"every 30m"`, `"every 2h"`, `"daily 09:00"`.
struct Schedule: Equatable {
    enum Kind: Equatable {
        case interval(TimeInterval)
        case daily(hour: Int, minute: Int)
    }

    let kind: Kind

    init?(_ configuration: String) {
        let parts = configuration.split(separator: " ")
        guard parts.count == 2 else { return nil }

        switch parts[0] {
        case "every":
            guard let unit = parts[1].last,
                  let value = Double(parts[1].dropLast()), value > 0 else { return nil }
            switch unit {
            case "m": kind = .interval(value * 60)
            case "h": kind = .interval(value * 3600)
            default: return nil
            }
        case "daily":
            let time = parts[1].split(separator: ":")
            guard time.count == 2,
                  let hour = Int(time[0]), (0...23).contains(hour),
                  let minute = Int(time[1]), (0...59).contains(minute) else { return nil }
            kind = .daily(hour: hour, minute: minute)
        default:
            return nil
        }
    }

    /// Interval schedules fire when the last run is older than the interval
    /// (or never happened). Daily schedules fire on the first tick at/after
    /// the target time that hasn't already run since that time today.
    func isDue(now: Date, lastRunStart: Date?) -> Bool {
        switch kind {
        case .interval(let seconds):
            guard let last = lastRunStart else { return true }
            return now.timeIntervalSince(last) >= seconds
        case .daily(let hour, let minute):
            guard let todayAt = Calendar.current.date(
                bySettingHour: hour, minute: minute, second: 0, of: now
            ), now >= todayAt else { return false }
            guard let last = lastRunStart else { return true }
            return last < todayAt
        }
    }

    /// "Every 30m" / "Daily at 09:00" — for subtitles and the Schedule sheet.
    var displayText: String {
        switch kind {
        case .interval(let seconds):
            let minutes = Int(seconds / 60)
            return minutes % 60 == 0 && minutes >= 60
                ? "Every \(minutes / 60)h"
                : "Every \(minutes)m"
        case .daily(let hour, let minute):
            return String(format: "Daily at %02d:%02d", hour, minute)
        }
    }
}
