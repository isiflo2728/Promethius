import Foundation
import EventKit
import AgentKit

/// EventKit-backed `UpcomingEventProviding`: the user's real calendar events
/// for the next 7 days, feeding the Today view's "What's next" section.
///
/// Requires the `com.apple.security.personal-information.calendars`
/// entitlement and `NSCalendarsFullAccessUsageDescription` — both set on the
/// AgentHubMac target.
@MainActor
final class CalendarService: UpcomingEventProviding {
    private let store = EKEventStore()

    func upcomingEvents(limit: Int) async -> CalendarState {
        guard await ensureAccess() else { return .accessDenied }

        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else {
            return .events([])
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { event in
                UpcomingEvent(
                    title: event.title ?? "Untitled event",
                    subtitle: event.location ?? "",
                    timeLabel: Self.timeLabel(for: event)
                )
            }
        return .events(Array(events))
    }

    /// True once the app has full calendar access, prompting the first time.
    private func ensureAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default:
            return false
        }
    }

    /// "Today, 2:30 PM" / "Tomorrow, all day" / "Friday, 10:00 AM" — matches
    /// the compact style the event rows render.
    private static func timeLabel(for event: EKEvent) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(event.startDate) {
            day = "Today"
        } else if calendar.isDateInTomorrow(event.startDate) {
            day = "Tomorrow"
        } else {
            day = event.startDate.formatted(.dateTime.weekday(.wide))
        }
        if event.isAllDay {
            return "\(day), all day"
        }
        return "\(day), \(event.startDate.formatted(date: .omitted, time: .shortened))"
    }
}
