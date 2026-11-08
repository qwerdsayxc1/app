import Foundation

/// Распознаёт голосовой ответ на запрос подтверждения (ru / uk / en / de).
/// Неоднозначный ответ трактуется как отсутствие ответа (nil), а не как согласие.
public enum ConfirmationParser {
    private static let positive: Set<String> = [
        "да", "давай", "подтверждаю", "конечно", "выполняй", "можно", "ага", "угу",
        "так", "підтверджую", "звісно", "виконуй",
        "yes", "yeah", "yep", "sure", "confirm", "ok", "okay", "go",
        "ja", "jawohl", "bestätigen", "klar"
    ]

    private static let negative: Set<String> = [
        "нет", "не", "не надо", "отмена", "отмени", "стоп", "не нужно",
        "ні", "скасуй", "не треба",
        "no", "nope", "cancel", "stop", "don't",
        "nein", "abbrechen", "nicht"
    ]

    public static func parse(_ utterance: String) -> Bool? {
        let normalized = AppAliasResolver.normalize(utterance)
        guard !normalized.isEmpty else { return nil }
        let words = normalized.split(separator: " ").map(String.init)

        // Фразы целиком («не надо», «не треба») и отрицания имеют приоритет: «да нет» → нет.
        let normalizedNegative = Set(negative.map(AppAliasResolver.normalize))
        let normalizedPositive = Set(positive.map(AppAliasResolver.normalize))
        if normalizedNegative.contains(normalized) { return false }
        if words.contains(where: { normalizedNegative.contains($0) }) { return false }
        if normalizedPositive.contains(normalized) { return true }
        if let first = words.first, normalizedPositive.contains(first) { return true }
        return nil
    }
}
