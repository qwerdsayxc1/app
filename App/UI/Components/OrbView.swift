import SwiftUI
import NOVACore

/// Большой анимированный AI Orb. Цвет зависит от состояния, размер «дышит» и реагирует на голос.
struct OrbView: View {
    let status: AssistantStatus
    let level: Float
    var size: CGFloat = 240

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize, time: time)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("NOVA: \(status.title)")
    }

    private func draw(in context: inout GraphicsContext, size canvasSize: CGSize, time: TimeInterval) {
        let (primary, secondary) = Theme.colors(for: status)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let base = min(canvasSize.width, canvasSize.height) / 2

        let speed: Double
        switch status {
        case .idle: speed = 0.6
        case .listening: speed = 1.6
        case .thinking: speed = 2.4
        case .executing: speed = 2.0
        case .speaking: speed = 1.8
        }
        let breathing = 1 + 0.035 * sin(time * speed * 1.4)
        let voiceBoost = 1 + CGFloat(level) * 0.22
        let radius = base * 0.56 * breathing * voiceBoost

        // Внешнее свечение
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: base * 0.18))
            let glowRect = CGRect(x: center.x - radius * 1.25, y: center.y - radius * 1.25, width: radius * 2.5, height: radius * 2.5)
            layer.fill(Path(ellipseIn: glowRect), with: .radialGradient(
                Gradient(colors: [primary.opacity(0.55), secondary.opacity(0.25), .clear]),
                center: center, startRadius: 0, endRadius: radius * 1.25
            ))
        }

        // Ядро
        let coreRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: coreRect), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.95), primary, secondary.opacity(0.9), Color.black.opacity(0.85)]),
            center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.3),
            startRadius: radius * 0.02,
            endRadius: radius * 1.15
        ))

        // Вращающиеся световые «ленты» внутри сферы
        context.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: coreRect))
            layer.addFilter(.blur(radius: radius * 0.12))
            for index in 0..<3 {
                let phase = time * speed * (0.5 + Double(index) * 0.22) + Double(index) * 2.1
                let offset = CGPoint(x: cos(phase) * radius * 0.45, y: sin(phase * 1.3) * radius * 0.45)
                let blobRadius = radius * (0.45 + 0.1 * CGFloat(index))
                let blobRect = CGRect(x: center.x + offset.x - blobRadius, y: center.y + offset.y - blobRadius, width: blobRadius * 2, height: blobRadius * 2)
                let color = index.isMultiple(of: 2) ? secondary : primary
                layer.fill(Path(ellipseIn: blobRect), with: .color(color.opacity(0.55)))
            }
        }

        // Орбитальное кольцо
        var ring = Path()
        ring.addEllipse(in: coreRect.insetBy(dx: -radius * 0.12, dy: -radius * 0.12))
        let rotation = Angle.radians(time * speed * 0.6)
        context.stroke(ring, with: .conicGradient(
            Gradient(colors: [primary.opacity(0.0), primary.opacity(0.9), secondary.opacity(0.9), secondary.opacity(0.0)]),
            center: center,
            angle: rotation
        ), lineWidth: 1.6)
    }
}
