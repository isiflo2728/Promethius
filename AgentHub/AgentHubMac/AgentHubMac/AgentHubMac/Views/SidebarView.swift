import SwiftUI
import AgentKit

/// Top-level navigation for the Mac window: sections for mission control,
enum NavSelection : Hashable {
    case missionControl
    case overView
    case models
    case agent1
    case agent2
}
/// connected accounts, and settings.
struct SidebarView: View {
    
    @State var selection: NavSelection = .missionControl
    
    var body: some View {
        List(selection: $selection) {
            Section("Work Space") {
                Label("Control", systemImage: "square.grid.2x2")
                    .tag(NavSelection.missionControl)
                Label("Pulse", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(NavSelection.overView)
                Label("Models", systemImage: "sparkles")
                    .tag(NavSelection.models)
            }
            Section("Agents") {
                // replace with agents user has
                Label("Agent 1", systemImage: "brain.head.profile")
                    .tag(NavSelection.agent1)
                Label("Agent 2", systemImage: "brain.head.profile")
                    .tag(NavSelection.agent2)
            } 
        }
        .listStyle(.sidebar)
        .navigationTitle("AgentHub")
    }
}
