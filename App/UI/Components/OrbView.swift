import SwiftUI
import NOVACore

/// Большой анимированный AI Orb. Цвет зависит от состояния, размер «дышит» и реагирует на голос.
struct OrbView: View {
    let status: AssistantStatus
    let level: Float
    var size: CGFloat = 240

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let (primary, secondary) = Theme.colors(for: status)
        let speed = Self.speed(for: status)
        let level = self.level
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                OrbView.draw(in: &context, size: canvasSize, time: time, primary: primary, secondary: secondary, speed: speed, level: level)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("NOVA: \(status.title)")
    }

    private nonisolated static func speed(for status: AssistantStatus) -> Double {
        switch status {
        case .idle: return 0.6
        case .listening: return 1.6
        case .thinking: return 2.4
        case .executing: return 2.0
        case .speaking: return 1.8
        }
    }

    private nonisolated static func circle(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// Вся арифметика в явных CGFloat — без неявных преобразований Double↔CGFloat.
    private nonisolated static func draw(
        in context: inout GraphicsContext,
        size canvasSize: CGSize,
        time: TimeInterval,
        primary: Color,
        secondary: Color,
        speed: Double,
        level: Float
    ) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let base: CGFloat = min(canvasSize.width, canvasSize.height) / 2
        let breathing = CGFloat(1.0 + 0.035 * sin(time * speed * 1.4))
        let voiceBoost: CGFloat = 1 + CGFloat(level) * 0.22
        let radius: CGFloat = base * 0.56 * breathing * voiceBoost

        // Внешнее свечение
        let glowRadius: CGFloat = radius * 1.25
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: base * 0.18))
            layer.fill(
                Path(ellipseIn: circle(center: center, radius: glowRadius)),
                with: .radialGradient(
                    Gradient(colors: [primary.opacity(0.55), secondary.opacity(0.25), Color.clear]),
                    center: center,
                    startRadius: 0,
                    endRadius: glowRadius
                )
            )
        }

        // Ядро
        let coreRect = circle(center: center, radius: radius)
        let highlight = CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.3)
        let coreGradient = Gradient(colors: [Color.white.opacity(0.95), primary, secondary.opacity(0.9), Color.black.opacity(0.85)])
        context.fill(
            Path(ellipseIn: coreRect),
            with: .radialGradient(coreGradient, center: highlight, startRadius: radius * 0.02, endRadius: radius * 1.15)
        )

        // Вращающиеся световые «ленты» внутри сферы
        context.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: coreRect))
            layer.addFilter(.blur(radius: radius * 0.12))
            for index in 0..<3 {
                let step = Double(index)
                let phase: Double = time * speed * (0.5 + step * 0.22) + step * 2.1
                let dx: CGFloat = CGFloat(cos(phase)) * radius * 0.45
                let dy: CGFloat = CGFloat(sin(phase * 1.3)) * radius * 0.45
                let blobRadius: CGFloat = radius * (0.45 + 0.1 * CGFloat(index))
                let blobCenter = CGPoint(x: center.x + dx, y: center.y + dy)
                let color = index.isMultiple(of: 2) ? secondary : primary
                layer.fill(Path(ellipseIn: circle(center: blobCenter, radius: blobRadius)), with: .color(color.opacity(0.55)))
            }
        }

        // Орбитальное кольцо
        let inset: CGFloat = -radius * 0.12
        let ring = Path(ellipseIn: coreRect.insetBy(dx: inset, dy: inset))
        let ringGradient = Gradient(colors: [primary.opacity(0.0), primary.opacity(0.9), secondary.opacity(0.9), secondary.opacity(0.0)])
        context.stroke(
            ring,
            with: .conicGradient(ringGradient, center: center, angle: Angle.radians(time * speed * 0.6)),
            lineWidth: 1.6
        )
    }
}
