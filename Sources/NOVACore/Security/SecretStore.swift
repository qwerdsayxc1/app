import Foundation

/// Хранилище секрета (API-ключа). В приложении — Keychain, в тестах — память.
/// Ключ никогда не хранится в коде, UserDefaults или файлах.
public protocol SecretStoring: Sendable {
    func readAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

public enum SecretStoreError: Error, Equatable, Sendable, LocalizedError {
    case invalidKeyFormat
    case keychain(status: Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidKeyFormat:
            return "Это не похоже на API-ключ Anthropic (ожидается строка, начинающаяся с sk-ant-)."
        case .keychain(let status):
            return "Ошибка Keychain (код \(status))."
        }
    }
}

/// Проверка формата ключа перед сохранением (без сетевых запросов).
public enum APIKeyValidator {
    public static func normalized(_ raw: String) throws -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-ant-"),
              (20...400).contains(key.count),
              key.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            throw SecretStoreError.invalidKeyFormat
        }
        return key
    }

    /// Маска для отображения в UI: sk-ant-…ABCD.
    public static func masked(_ key: String) -> String {
        guard key.count > 12 else { return "••••" }
        return "sk-ant-…" + key.suffix(4)
    }
}

/// Потокобезопасное хранилище секрета в памяти.
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    public init(key: String? = nil) {
        self.key = key
    }

    public func readAPIKey() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return key
    }

    public func saveAPIKey(_ key: String) throws {
        let normalized = try APIKeyValidator.normalized(key)
        lock.lock(); defer { lock.unlock() }
        self.key = normalized
    }

    public func deleteAPIKey() throws {
        lock.lock(); defer { lock.unlock() }
        key = nil
    }
}
