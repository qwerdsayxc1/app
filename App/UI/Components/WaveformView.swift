import SwiftUI
import NOVACore

/// Светящаяся звуковая волна. Амплитуда следует за уровнем микрофона,
/// в остальных состояниях — спокойная «дышащая» линия.
struct WaveformView: View {
    let status: AssistantStatus
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let (primary, secondary) = Theme.colors(for: status)
                let amplitude = baseAmplitude * size.height * 0.45
                for layer in 0..<3 {
                    let path = wavePath(size: size, time: time, layer: layer, amplitude: amplitude)
                    let opacity = 1.0 - Double(layer) * 0.3
                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius: 6))
                        glow.stroke(path, with: .color(primary.opacity(0.5 * opacity)), lineWidth: 4)
                    }
                    context.stroke(path, with: .linearGradient(
                        Gradient(colors: [primary.opacity(0), primary.opacity(opacity), secondary.opacity(opacity), secondary.opacity(0)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ), lineWidth: 1.6)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var baseAmplitude: CGFloat {
        switch status {
        case .listening: return 0.12 + CGFloat(level) * 0.88
        case .speaking: return 0.45
        case .thinking, .executing: return 0.25
        case .idle: return 0.06
        }
    }

    private func wavePath(size: CGSize, time: TimeInterval, layer: Int, amplitude: CGFloat) -> Path {
        var path = Path()
        let midY = size.height / 2
        let frequency = 2.0 + Double(layer) * 0.7
        let speed = 2.2 + Double(layer) * 0.8
        let steps = max(Int(size.width / 3), 2)
        for step in 0...steps {
            let x = CGFloat(step) / CGFloat(steps) * size.width
            let progress = Double(x / max(size.width, 1))
            // Огибающая: волна затухает к краям.
            let envelope = sin(progress * .pi)
            let y = midY + CGFloat(sin(progress * .pi * 2 * frequency + time * speed) * envelope) * amplitude * (1 - CGFloat(layer) * 0.25)
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
