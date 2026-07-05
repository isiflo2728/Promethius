import WidgetKit
import SwiftUI
import AgentKit

/// Lock-screen / home-screen widget showing live agent status.
///
/// CloudKit note: the widget reads the same synced store but refreshes on the
/// system's timeline cadence, so it can trail the app by a bit. Treat its
/// numbers as "recently synced," never authoritative — the app is the source
/// of truth for taking action.
struct AgentStatusWidget: Widget {
    let kind = "AgentStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentStatusProvider()) { entry in
            AgentStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Agent Status")
        .description("Running agents and pending approvals.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct AgentStatusEntry: TimelineEntry {
    let date: Date
    let running: Int
    let waiting: Int
}

struct AgentStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgentStatusEntry {
        AgentStatusEntry(date: .now, running: 2, waiting: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (AgentStatusEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentStatusEntry>) -> Void) {
        // TODO: read counts from the shared (App Group) ModelContainer.
        let entry = placeholder(in: context)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct AgentStatusWidgetView: View {
    let entry: AgentStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(entry.running) running", systemImage: "play.circle")
            Label("\(entry.waiting) waiting", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
        .font(.caption)
    }
}
