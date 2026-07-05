import SwiftUI

/// Minimal line sparkline for an agent's recent activity. Pure SwiftUI Shape,
/// no dependencies.
struct ActivitySparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            path(in: geo.size)
                .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func path(in size: CGSize) -> Path {
        Path { path in
            guard values.count > 1, let minV = values.min(), let maxV = values.max() else { return }
            let range = max(maxV - minV, 0.0001)
            let stepX = size.width / CGFloat(values.count - 1)
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let y = size.height * (1 - CGFloat((value - minV) / range))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}
