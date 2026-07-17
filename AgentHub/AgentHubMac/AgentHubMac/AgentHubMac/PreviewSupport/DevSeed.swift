#if DEBUG
import Foundation
import SwiftData
import AgentKit
import OSLog

/// One-time development seed so the *running* app shows sample content without
/// waiting on the agent runner (which is still a stub). Compiled only in DEBUG.
/// Each record type is seeded independently and only when that type is empty,
/// so it fills gaps even if the store already has some data (e.g. agents you
/// created by hand) and never duplicates on relaunch.
@MainActor
enum DevSeed {
    private static let log = Logger(subsystem: "AgentHubMac", category: "DevSeed")

    /// Guard so sample content is inserted at most once per install. The
    /// previous approach (re-insert any sample missing "by name" on every
    /// launch) meant deleting a sample agent only lasted until the next
    /// relaunch resurrected it. Bump the suffix to force one re-seed after
    /// changing the samples below.
    private static let didSeedKey = "DevSeed.didSeed.v2"

    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didSeedKey) else { return }
        UserDefaults.standard.set(true, forKey: didSeedKey)

        let existing = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let existingNames = Set(existing.map(\.name))

        // Agents — insert any sample that's missing by name, so this one-time
        // seed fills gaps even on a store that already holds hand-made agents.
        // Most are `.running` so Mission Control — which shows running agents
        // only — has a full grid; a couple stay idle/waiting to exercise Pulse.
        let sampleAgents: [(name: String, summary: String, status: AgentStatus)] = [
            ("Inbox Triage", "Sorts new mail and drafts quick replies for review.", .running),
            ("Meeting Notetaker", "Joins calls and turns them into shared summaries.", .running),
            ("Repo Sentinel", "Watches CI and surfaces failing checks as they land.", .running),
            ("Expense Sorter", "Categorizes receipts and flags anything over budget.", .running),
            ("Standup Notes", "Summarizes yesterday's activity into a morning digest.", .idle),
            ("PR Watcher", "Watches the repo and pings you when a review is requested.", .waitingApproval),
            ("Code Reviewer", "Reviews staged diffs before push and flags risky changes.", .failed),
        ]
        let added = sampleAgents.filter { !existingNames.contains($0.name) }
        added.forEach { context.insert(Agent(name: $0.name, summary: $0.summary, status: $0.status)) }
        if !added.isEmpty { log.debug("Seeded \(added.count) agents") }

        // Re-fetch so the approval/insight links below resolve whether the
        // agents were just inserted now or already existed.
        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let inbox = agents.first { $0.name == "Inbox Triage" }
        let standup = agents.first { $0.name == "Standup Notes" }

        // Fill each agent's detail (model, trigger, permissions, run log) so
        // the detail view renders fully. Idempotent — only fills empties.
        agents.forEach { applyDetail(to: $0, context: context) }

        // "Needs you" — the sample approvals. Two carry an editable draft body;
        // the calendar invite has nothing to edit.
        let approvalSpecs: [(title: String, detail: String, draft: String, tool: String, agentName: String?)] = [
            ("Reply ready to send",
             "Re: \u{201C}Q3 budget review\u{201D} — to Sam",
             "Revised numbers by Friday. Can we push the call to Monday?",
             "composio.gmail.send", "Inbox Triage"),
            ("Post standup to Slack",
             "To #engineering",
             "Yesterday: shipped sidebar nav. Today: wiring the agent runner. No blockers so far.",
             "composio.slack.send", "Standup Notes"),
            ("Send calendar invite",
             "\u{201C}Design review\u{201D} Thursday 3:00–3:30 PM with Sam and Alex — agenda: sign off the onboarding copy.",
             "", "composio.googlecalendar.create", "Inbox Triage"),
        ]

        // Filter in Swift (not via #Predicate) to avoid captured-value quirks.
        let allApprovals = (try? context.fetch(FetchDescriptor<PendingApproval>())) ?? []
        let pending = allApprovals.filter { $0.status == .pending }

        if pending.isEmpty {
            // Fresh seed — reappears on relaunch after you approve/discard.
            for spec in approvalSpecs {
                let approval = PendingApproval(
                    title: spec.title, detail: spec.detail,
                    draftBody: spec.draft, proposedToolName: spec.tool
                )
                approval.agent = agents.first { $0.name == spec.agentName }
                context.insert(approval)
            }
            log.debug("Seeded \(approvalSpecs.count) pending approvals")
        } else {
            // Backfill drafts onto approvals created before draftBody existed,
            // so their Edit button appears without wiping the store.
            for approval in pending where approval.draftBody.isEmpty {
                if let spec = approvalSpecs.first(where: { $0.title == approval.title }),
                   !spec.draft.isEmpty {
                    approval.draftBody = spec.draft
                    approval.detail = spec.detail
                    log.debug("Backfilled draft for \(approval.title, privacy: .public)")
                }
            }
        }

        // "Recent insights".
        let insights = (try? context.fetch(FetchDescriptor<Insight>())) ?? []
        if insights.isEmpty {
            let summary = Insight(
                title: "Design Sync — summary",
                source: "Meeting Notes",
                kind: .summary,
                iconName: "clock",
                detail: "Agreed to ship the new onboarding by Friday; Sam owns the copy pass.",
                bullets: ["Finalize onboarding copy — Sam",
                          "Revised budget numbers by Fri",
                          "Book follow-up for Monday"]
            )
            summary.agent = standup

            let digest = Insight(
                title: "This week",
                source: "Calendar watch",
                kind: .digest,
                iconName: "calendar",
                detail: "4 upcoming items across the week — here's what's next.",
                bullets: ["Design Sync — today 2:30 PM",
                          "PR review due — today 5:00 PM",
                          "1:1 with Sam — Thu 11:00 AM"]
            )

            let prNote = Insight(
                title: "PR #142 needs a nudge",
                source: "PR Watcher",
                kind: .note,
                iconName: "arrow.triangle.pull",
                detail: "Open two days with no review, and you're the requested reviewer.",
                bullets: ["Touches AgentRunner + tools",
                          "1 failing check: unit tests",
                          "Author pinged twice"]
            )

            let inboxInsight = Insight(
                title: "Inbox triaged",
                source: "Inbox Triage",
                kind: .summary,
                iconName: "tray.full",
                detail: "Sorted 18 new messages; a few need you, the rest are handled.",
                bullets: ["3 flagged for a reply",
                          "2 drafts ready to review",
                          "13 archived automatically"]
            )

            let metrics = Insight(
                title: "Weekly metrics",
                source: "Standup Notes",
                kind: .digest,
                iconName: "chart.bar",
                detail: "Activity is up week-over-week; here's the shape of it.",
                bullets: ["12 PRs merged (+3)",
                          "4 agents active",
                          "0 failed runs"]
            )

            [summary, digest, prNote, inboxInsight, metrics].forEach(context.insert)
            log.debug("Seeded 5 insights")
        }

        do {
            try context.save()
            log.debug("DevSeed save OK — approvals now, insights now")
        } catch {
            log.error("DevSeed save FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Per-agent detail seed

    /// The sample model, trigger, permissions, and run log for one agent.
    struct DetailSpec {
        let model: String
        let triggerKind: TriggerKind
        let triggerConfig: String
        let permissions: [(scope: PermissionScope, enabled: Bool)]
        /// `ago` is a negative offset from now, so entries read as "6m ago".
        let log: [(kind: LogKind, message: String, ago: TimeInterval)]
    }

    /// Attaches a `DetailSpec` to an agent so the detail view renders fully.
    /// Shared by the running-app seed and `PreviewData`. Only fills empties, so
    /// it's safe to call on agents that already have some detail.
    static func applyDetail(to agent: Agent, context: ModelContext) {
        let spec = detail(forName: agent.name)

        if agent.modelName.isEmpty { agent.modelName = spec.model }

        if (agent.triggers ?? []).isEmpty {
            let trigger = Trigger(kind: spec.triggerKind, configuration: spec.triggerConfig)
            trigger.agent = agent
            context.insert(trigger)
        }

        if (agent.permissions ?? []).isEmpty {
            for entry in spec.permissions {
                let permission = Permission(scope: entry.scope, isEnabled: entry.enabled)
                permission.agent = agent
                context.insert(permission)
            }
        }

        if (agent.runLog ?? []).isEmpty {
            for entry in spec.log {
                let logEntry = RunLogEntry(kind: entry.kind, message: entry.message)
                logEntry.timestamp = Date().addingTimeInterval(entry.ago)
                logEntry.agent = agent
                context.insert(logEntry)
            }
        }
    }

    private static func detail(forName name: String) -> DetailSpec {
        switch name {
        case "Code Reviewer":
            return DetailSpec(
                model: "DeepSeek Coder 6.7B",
                triggerKind: .fileChange, triggerConfig: "git commit",
                permissions: [(.localGit, true), (.webFetch, false), (.composioGitHub, true)],
                log: [
                    (.error, "Local model unreachable mid-review of \u{201C}fix: auth retry loop.\u{201D} Reload the model to finish.", -360),
                    (.toolResult, "Reviewed \u{201C}fix: auth retry loop\u{201D}", -10_800),
                ]
            )
        case "Repo Sentinel":
            return DetailSpec(
                model: "DeepSeek Coder 6.7B",
                triggerKind: .fileChange, triggerConfig: "git commit",
                permissions: [(.localGit, true), (.webFetch, false), (.composioGitHub, true)],
                log: [
                    (.error, "Could not reach local model — reload needed", -360),
                    (.toolResult, "Reviewed \u{201C}fix: auth retry loop\u{201D}", -10_800),
                ]
            )
        case "Inbox Triage":
            return DetailSpec(
                model: "Llama 3.1 8B",
                triggerKind: .composioEvent, triggerConfig: "new email",
                permissions: [(.composioGmail, true), (.webFetch, true)],
                log: [
                    (.toolResult, "Drafted a reply to Sam", -600),
                    (.thought, "Sorting 18 new messages", -1_800),
                ]
            )
        case "Meeting Notetaker":
            return DetailSpec(
                model: "Whisper + Llama 3.1 8B",
                triggerKind: .composioEvent, triggerConfig: "calendar event",
                permissions: [(.localCalendar, true), (.composioNotion, true)],
                log: [
                    (.toolResult, "Summarized Design Sync", -900),
                    (.thought, "Transcribing call audio", -2_400),
                ]
            )
        case "Expense Sorter":
            return DetailSpec(
                model: "Phi-3 Mini",
                triggerKind: .schedule, triggerConfig: "daily at 9am",
                permissions: [(.localFiles, true), (.composioNotion, false)],
                log: [
                    (.toolResult, "Categorized 12 receipts", -1_200),
                    (.thought, "Flagged 1 charge over budget", -4_200),
                ]
            )
        case "Standup Notes":
            return DetailSpec(
                model: "Llama 3.1 8B",
                triggerKind: .schedule, triggerConfig: "weekdays at 8am",
                permissions: [(.composioSlack, true), (.localCalendar, true)],
                log: [
                    (.toolResult, "Posted digest to #engineering", -3_600),
                ]
            )
        case "PR Watcher":
            return DetailSpec(
                model: "DeepSeek Coder 6.7B",
                triggerKind: .composioEvent, triggerConfig: "review requested",
                permissions: [(.composioGitHub, true), (.webFetch, true)],
                log: [
                    (.thought, "Waiting on your approval to comment", -300),
                    (.toolResult, "Fetched diff for PR #142", -5_400),
                ]
            )
        default:
            return DetailSpec(
                model: "Llama 3.1 8B",
                triggerKind: .manual, triggerConfig: "",
                permissions: [(.localFiles, true), (.webFetch, false)],
                log: [(.system, "Agent created", -600)]
            )
        }
    }
}
#endif
