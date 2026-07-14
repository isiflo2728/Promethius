import SwiftUI

/// A selectable pill for one-of-many choices (trigger, model). Carries the
/// `.isSelected` trait so VoiceOver announces the current pick.
struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(stroke))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)
    }

    private var stroke: Color {
        isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.12)
    }
}

#Preview {
    HStack {
        Chip(title: "Manual", isSelected: true) {}
        Chip(title: "Schedule", isSelected: false) {}
    }
    .padding()
}
