import Foundation
import UserNotifications
import AgentKit

/// Handles "needs attention" alerts on the iPhone — most importantly, an agent
/// entering `.waitingApproval` on the Mac.
///
/// Because CloudKit sync can lag, prefer a CloudKit *push* (silent
/// notification via a database subscription) to wake this app and pull the
/// latest, rather than relying on the user opening the app and waiting for a
/// periodic sync. The push is the low-latency signal; the synced store is the
/// source of truth once it arrives.
@MainActor
final class PushHandler: NSObject {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Called from a CloudKit silent push. Sync has (probably) just delivered a
    /// change; surface a local notification if something needs the user.
    func handleRemoteChange() {
        // TODO: fetch agents in `.waitingApproval` from the shared container and
        // post a local notification linking to that agent's detail screen.
    }

    func postApprovalNeeded(agentName: String, agentID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Approval needed"
        content.body = "\(agentName) is waiting for your approval."
        content.userInfo = ["agentID": agentID.uuidString]
        let request = UNNotificationRequest(identifier: agentID.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
