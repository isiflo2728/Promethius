import SwiftUI
import AgentKit

/// A read-only result an agent produced, shown in the Glance "Recent insights"
/// section — a summary with action items, a weekly digest, etc. Mirrors the
/// header layout of `ApprovalCard` so the two sections feel like one system.
struct InsightCard: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: icon · title/provenance
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.headline)
                    Text(provenance)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !insight.detail.isEmpty {
                Text(insight.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !insight.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(insight.bullets, id: \.self) { bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.tertiary)
                            Text(bullet)
                                .font(.callout.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Keep content top-aligned so every tile in the grid lines up,
            // matching ApprovalCard — uniform cards regardless of body length.
            Spacer(minLength: 0)
        }
        .padding(16)
        // Uniform tile size across the Glance grid — kept in sync with
        // ApprovalCard's frame. Taller content grows past this minimum.
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Insight: \(insight.title). \(insight.detail)")
    }

    /// "via <source> · <time> ago" line beneath the title.
    private var provenance: String {
        let source = insight.source.isEmpty
            ? (insight.agent?.name.isEmpty == false ? insight.agent!.name : "an agent")
            : insight.source
        let ago = insight.createdAt.formatted(.relative(presentation: .named))
        return "via \(source) · \(ago)"
    }
}

#Preview {
    VStack(spacing: 16) {
        InsightCard(insight: Insight(
            title: "Design Sync — summary",
            source: "Meeting Notes",
            kind: .summary,
            iconName: "clock",
            detail: "Agreed to ship the new onboarding by Friday; Sam owns the copy pass.",
            bullets: ["Finalize onboarding copy — Sam",
                      "Revised budget numbers by Fri",
                      "Book follow-up for Monday"]
        ))
        InsightCard(insight: Insight(
            title: "This week",
            source: "Calendar watch",
            kind: .digest,
            iconName: "calendar",
            detail: "4 upcoming items. Next: Design Sync at 2:30 PM, then a PR review due at 5:00 PM."
        ))
    }
    .padding()
    .frame(width: 380)
}
