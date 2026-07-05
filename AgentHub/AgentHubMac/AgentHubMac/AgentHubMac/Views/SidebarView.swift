import SwiftUI
import AgentKit

/// Top-level navigation for the Mac window: sections for mission control,
/// connected accounts, and settings.
struct SidebarView: View {
    var body: some View {
        List {
            Section("Agents") {
                Label("Mission Control", systemImage: "square.grid.2x2")
                Label("Orchestration", systemImage: "point.3.connected.trianglepath.dotted")
            }
            Section("Setup") {
                Label("Connections", systemImage: "link")
                Label("Local Models", systemImage: "cpu")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("AgentHub")
    }
}
