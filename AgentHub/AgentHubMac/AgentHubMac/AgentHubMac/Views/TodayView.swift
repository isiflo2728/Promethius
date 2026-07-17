import SwiftUI
import SwiftData
import AgentKit

/// The home tab: a greeting with live counts, an "ask anything" bar, the things
/// that need you (pending approvals + stalled agents), a cross-agent activity
/// feed, and a weekly recap with what's next.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State var viewModel: TodayViewModel

    /// Reply tone — a visual affordance for now, not yet persisted.
    @State private var tone: TodayTone = .neutral
    @State private var askText = ""
    /// Streams "ask anything" requests through the agent-harness backend.
    /// Owned by RootView (not @State here) so the conversation survives
    /// switching away from the Today tab — this view is destroyed and
    /// rebuilt on every tab switch, and a fresh ChatViewModel would mint a
    /// new server session ID and orphan the transcript.
    var chat: ChatViewModel = ChatViewModel()
    @State private var editingApproval: PendingApproval?
    @State private var editingDraft = ""
    @State private var openingAgent: Agent?

    private let columns = [GridItem(.flexible(), spacing: 20),
                           GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                greeting
                askBar
                askConversation
                needsYouSection
                onYourPlateSection
                thisWeekSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem {
                Picker("Tone", selection: $tone) {
                    ForEach(TodayTone.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .onAppear { viewModel.refresh() }
        .task {
            async let calendar: Void = viewModel.loadCalendar()
            async let plate: Void = viewModel.loadPlate()
            _ = await (calendar, plate)
        }
        .sheet(item: $editingApproval) { approval in
            DraftEditor(
                title: approval.title,
                text: $editingDraft,
                onSave: { saveDraft(approval) },
                onCancel: { editingApproval = nil }
            )
        }
        .sheet(item: $openingAgent) { agent in
            NavigationStack {
                AgentDetailView(
                    viewModel: AgentDetailViewModel(agent: agent, repository: repository)
                )
                .toolbar { Button("Done") { openingAgent = nil } }
            }
            .frame(minWidth: 720, minHeight: 520)
        }
    }

    private var repository: AgentRepository {
        AgentRepository(context: modelContext)
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(viewModel.greeting).")
                .font(.system(size: 40, weight: .bold))
            Text(viewModel.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Ask bar

    private var askBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            TextField(
                "Ask anything — \u{201C}draft a reply to Sam\u{201D}, \u{201C}what\u{2019}s on my plate today\u{201D}\u{2026}",
                text: $askText
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .onSubmit(sendAsk)
            if chat.isWorking {
                Button("Stop") { chat.cancel() }
                    .buttonStyle(.bordered)
            } else {
                Button("Go", action: sendAsk)
                    .buttonStyle(.borderedProminent)
                    .disabled(askText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }

    private func sendAsk() {
        let message = askText.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty, !chat.isWorking else { return }
        chat.send(message)
        askText = ""
    }

    // MARK: - Ask conversation

    /// The streamed back-and-forth under the ask bar. Hidden until the first
    /// question is asked.
    @ViewBuilder
    private var askConversation: some View {
        if !chat.transcript.isEmpty || chat.isWorking {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionLabel("Conversation")
                    Spacer()
                    Button("Clear") { chat.clear() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.transcript) { entry in
                        chatRow(entry)
                    }
                    if let status = chat.statusText {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(status)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .surface()
            }
        }
    }

    @ViewBuilder
    private func chatRow(_ entry: ChatEntry) -> some View {
        switch entry.kind {
        case .user:
            Text(entry.text)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12))
        case .assistant:
            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .thinking:
            Text(entry.text)
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .toolCall:
            Label(entry.text, systemImage: "wrench.and.screwdriver")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        case .toolResult:
            Label(entry.text, systemImage: "arrow.turn.down.right")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(4)
        case .error:
            Label(entry.text, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .notice:
            Text(entry.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Needs you

    private var needsYouSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Needs you", color: .mint)

            if viewModel.pendingApprovals.isEmpty && viewModel.stalledAgents.isEmpty {
                Text("You're all caught up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(viewModel.pendingApprovals) { approval in
                        approvalCard(approval)
                    }
                    ForEach(viewModel.stalledAgents) { agent in
                        stalledCard(agent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func approvalCard(_ approval: PendingApproval) -> some View {
        // A connect-account approval (it carries an OAuth link) needs the user
        // to open a page, not to send anything — different icon and actions.
        if let url = approval.actionURL {
            TodayAttentionCard(
                icon: "link",
                title: approval.title,
                provenance: provenance(agent: approval.agent, at: approval.createdAt),
                pillText: "Connect",
                pillColor: .mint,
                message: approval.detail,
                actions: [
                    CardAction(title: "Open Link", isProminent: true) {
                        openURL(url)
                        send(approval)
                    },
                    CardAction(title: "Dismiss", isProminent: false) { discard(approval) },
                ]
            )
        } else {
            TodayAttentionCard(
                icon: "envelope",
                title: approval.title,
                provenance: provenance(agent: approval.agent, at: approval.createdAt),
                pillText: "Approve",
                pillColor: .mint,
                message: message(for: approval),
                actions: [
                    CardAction(title: "Send", isProminent: true) { send(approval) },
                    CardAction(title: "Edit", isProminent: false) { beginEditing(approval) },
                    CardAction(title: "Save to Notes", isProminent: false) { saveToNotes(approval) },
                ]
            )
        }
    }

    private func stalledCard(_ agent: Agent) -> some View {
        TodayAttentionCard(
            icon: "exclamationmark.triangle",
            title: "\(agent.name) stalled",
            provenance: "via \(agent.name) · \(stalledTime(agent).formatted(.relative(presentation: .named)))",
            pillText: "Fix",
            pillColor: .mint,
            message: viewModel.reason(for: agent),
            actions: [
                CardAction(title: "Reload model", isProminent: true) { viewModel.retry(agent) },
                CardAction(title: "Open", isProminent: false) { openingAgent = agent },
            ]
        )
    }

    // MARK: - On your plate

    /// The agent's read of everything connected (email, GitHub, Slack, …),
    /// distilled into the things that need doing — replaces the old raw
    /// activity feed.
    private var onYourPlateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionLabel("On your plate")
                Spacer()
                if viewModel.isRefreshingPlate {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Updating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
                Button {
                    Task { await viewModel.loadPlate(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isPlateLoading || viewModel.isRefreshingPlate)
            }
            .animation(.default, value: viewModel.isRefreshingPlate)

            VStack(alignment: .leading, spacing: 0) {
                plateBody
            }
            .padding(16)
            .surface()
        }
    }

    private var isPlateLoading: Bool {
        if case .loading = viewModel.plateState { return true }
        return false
    }

    @ViewBuilder
    private var plateBody: some View {
        switch viewModel.plateState {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Going through your email, GitHub, and Slack…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        case .noSources:
            Text("Nothing to pull from yet — connect an account (Gmail, GitHub, Slack) and your to-dos will show up here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await viewModel.loadPlate(force: true) }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 6)
        case .briefing(let briefing):
            if !briefing.headline.isEmpty {
                Text(briefing.headline)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, briefing.items.isEmpty ? 0 : 8)
            }
            ForEach(Array(briefing.items.enumerated()), id: \.element.id) { index, item in
                plateRow(item)
                if index < briefing.items.count - 1 { Divider() }
            }
        }
    }

    private func plateRow(_ item: HarnessBriefing.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(urgencyColor(item.urgency))
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if !item.source.isEmpty {
                Label(item.source, systemImage: sourceIcon(item.source))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private func urgencyColor(_ urgency: HarnessBriefing.Item.Urgency) -> Color {
        switch urgency {
        case .now: .red
        case .today: .orange
        case .thisWeek: .secondary
        }
    }

    private func sourceIcon(_ source: String) -> String {
        let lowered = source.lowercased()
        if lowered.contains("mail") { return "envelope" }
        if lowered.contains("github") || lowered.contains("git") { return "arrow.triangle.branch" }
        if lowered.contains("slack") { return "bubble.left.and.bubble.right" }
        if lowered.contains("calendar") { return "calendar" }
        return "tray"
    }

    // MARK: - This week

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("This week")

            VStack(alignment: .leading, spacing: 18) {
                Text(viewModel.weeklySummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        sectionLabel("What's next", color: .mint)
                        Spacer()
                        // Re-reads the Mac's local EventKit store. It can't
                        // make macOS fetch from Google any sooner — that's
                        // the system's own sync cycle.
                        Button {
                            Task { await viewModel.loadCalendar() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    whatsNext
                    Button {
                        openCalendarApp()
                    } label: {
                        Text("See full calendar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(20)
            .surface()
        }
    }

    /// The "What's next" body — real calendar events, or the state that
    /// explains why there aren't any.
    @ViewBuilder
    private var whatsNext: some View {
        switch viewModel.calendarState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking your calendar…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .noProvider:
            Text("Calendar isn't connected.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .accessDenied:
            VStack(alignment: .leading, spacing: 10) {
                Text("AgentHub doesn't have calendar access, so it can't show what's coming up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Grant Access in System Settings") {
                    openCalendarPrivacySettings()
                }
                .buttonStyle(.bordered)
            }
        case .events(let events):
            if events.isEmpty {
                Text("Nothing on your calendar for the next 7 days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func openCalendarApp() {
        if let url = URL(string: "ical://") {
            openURL(url)
        }
    }

    private func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            openURL(url)
        }
    }

    private func eventRow(_ event: UpcomingEvent) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.headline)
                if !event.subtitle.isEmpty {
                    Text(event.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(event.timeLabel)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, color: Color = .secondary) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(color)
    }

    private func provenance(agent: Agent?, at date: Date) -> String {
        let name = (agent?.name.isEmpty == false) ? agent!.name : "an agent"
        return "via \(name) · \(date.formatted(.relative(presentation: .named)))"
    }

    private func message(for approval: PendingApproval) -> String {
        guard !approval.draftBody.isEmpty else { return approval.detail }
        return "\(approval.detail) — drafted: \u{201C}\(approval.draftBody)\u{201D}"
    }

    private func stalledTime(_ agent: Agent) -> Date {
        (agent.runLog ?? [])
            .filter { $0.kind == .error }
            .map(\.timestamp)
            .max() ?? agent.updatedAt
    }

    // MARK: - Actions

    private func send(_ approval: PendingApproval) {
        try? repository.resolve(approval, as: .approved)
        viewModel.refresh()
    }

    private func discard(_ approval: PendingApproval) {
        try? repository.resolve(approval, as: .discarded)
        viewModel.refresh()
    }

    private func beginEditing(_ approval: PendingApproval) {
        editingDraft = approval.draftBody
        editingApproval = approval
    }

    private func saveDraft(_ approval: PendingApproval) {
        try? repository.updateDraft(approval, to: editingDraft)
        editingApproval = nil
        viewModel.refresh()
    }

    private func saveToNotes(_ approval: PendingApproval) {
        let note = Insight(
            title: approval.title,
            source: "Saved from Today",
            kind: .note,
            iconName: "note.text",
            detail: approval.draftBody.isEmpty ? approval.detail : approval.draftBody
        )
        modelContext.insert(note)
        try? repository.resolve(approval, as: .discarded)
        viewModel.refresh()
    }
}

// MARK: - Attention card

private struct CardAction: Identifiable {
    let id = UUID()
    let title: String
    let isProminent: Bool
    let action: () -> Void
}

/// One "Needs you" card — an approval or a stalled agent. Both share the icon /
/// title / provenance / pill / message / actions shape.
private struct TodayAttentionCard: View {
    let icon: String
    let title: String
    let provenance: String
    let pillText: String
    let pillColor: Color
    let message: String
    let actions: [CardAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(provenance)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(pillText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(pillColor.opacity(0.5)))
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                ForEach(actions) { action in
                    if action.isProminent {
                        Button(action.title, action: action.action)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(action.title, action: action.action)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }
}

// MARK: - Tone

private enum TodayTone: String, CaseIterable, Identifiable {
    case technical, neutral, light
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

// MARK: - Card surface

private struct TodaySurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.quaternary))
    }
}

private extension View {
    func surface() -> some View { modifier(TodaySurface()) }
}

/// Canned events so the preview shows the populated "What's next" state
/// instead of a live EventKit fetch.
private struct PreviewEventProvider: UpcomingEventProviding {
    func upcomingEvents(limit: Int) async -> CalendarState {
        .events([
            UpcomingEvent(title: "Design Sync", subtitle: "Conference Room B", timeLabel: "Today, 2:30 PM"),
            UpcomingEvent(title: "1:1 w/ Sam", subtitle: "", timeLabel: "Tomorrow, 10:00 AM"),
        ])
    }
}

#Preview {
    TodayView(viewModel: TodayViewModel(
        repository: PreviewData.repository,
        eventProvider: PreviewEventProvider()
    ))
    .frame(width: 1000, height: 820)
    .modelContainer(PreviewData.container)
}
