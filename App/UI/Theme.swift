import SwiftUI
import NOVACore

/// Палитра NOVA: чёрный/графит, фиолетовые и синие акценты, неоновое свечение.
enum Theme {
    static let background = Color(red: 0.03, green: 0.03, blue: 0.05)
    static let graphite = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let violet = Color(red: 0.55, green: 0.36, blue: 1.0)
    static let blue = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let cyan = Color(red: 0.30, green: 0.85, blue: 1.0)
    static let magenta = Color(red: 0.90, green: 0.35, blue: 0.95)
    static let mint = Color(red: 0.35, green: 0.95, blue: 0.75)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.45)

    static let backgroundGradient = LinearGradient(
        colors: [background, graphite, Color(red: 0.06, green: 0.04, blue: 0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(colors: [violet, blue], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Основной и дополнительный цвет свечения для каждого состояния.
    static func colors(for status: AssistantStatus) -> (Color, Color) {
        switch status {
        case .idle: return (violet, blue)
        case .listening: return (cyan, blue)
        case .thinking: return (violet, magenta)
        case .executing: return (blue, mint)
        case .speaking: return (magenta, violet)
        }
    }

    static func statusTitle(_ status: AssistantStatus) -> String {
        status.title
    }
}

/// Фон окна: градиент + мягкие цветные пятна.
struct NovaBackground: View {
    var body: some View {
        ZStack {
            Theme.backgroundGradient
            Circle()
                .fill(Theme.violet.opacity(0.18))
                .frame(width: 520)
                .blur(radius: 140)
                .offset(x: -260, y: -220)
            Circle()
                .fill(Theme.blue.opacity(0.14))
                .frame(width: 460)
                .blur(radius: 140)
                .offset(x: 300, y: 260)
        }
        .ignoresSafeArea()
    }
}
