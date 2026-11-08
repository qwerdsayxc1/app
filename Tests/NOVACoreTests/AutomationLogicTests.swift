import XCTest
@testable import NOVACore

final class AutomationLogicTests: XCTestCase {
    // MARK: Алиасы приложений

    func testAliasesInSeveralLanguages() {
        let resolver = AppAliasResolver()
        XCTAssertEqual(resolver.resolve("Телеграм")?.canonicalName, "Telegram")
        XCTAssertEqual(resolver.resolve("telegram")?.canonicalName, "Telegram")
        XCTAssertEqual(resolver.resolve("IntelliJ IDEA")?.canonicalName, "IntelliJ IDEA")
        XCTAssertEqual(resolver.resolve("интеллидж")?.canonicalName, "IntelliJ IDEA")
        XCTAssertEqual(resolver.resolve("VS Code")?.canonicalName, "Visual Studio Code")
        XCTAssertEqual(resolver.resolve("vscode")?.canonicalName, "Visual Studio Code")
        XCTAssertEqual(resolver.resolve("Сафари")?.canonicalName, "Safari")
        XCTAssertEqual(resolver.resolve("Systemeinstellungen")?.canonicalName, "System Settings")
        XCTAssertNil(resolver.resolve("совершенно неизвестное"))
        XCTAssertNil(resolver.resolve(""))
    }

    func testMatchScore() {
        XCTAssertEqual(AppAliasResolver.matchScore(query: "Telegram", candidate: "Telegram"), 100)
        XCTAssertGreaterThan(AppAliasResolver.matchScore(query: "intellij", candidate: "IntelliJ IDEA Ultimate"), 0)
        XCTAssertEqual(AppAliasResolver.matchScore(query: "xy", candidate: "Xcode Beta"), 0)
    }

    // MARK: URL

    func testSearchURLs() throws {
        let google = try XCTUnwrap(WebURLBuilder.searchURL(engine: "google", query: "Claude API"))
        XCTAssertEqual(google.absoluteString, "https://www.google.com/search?q=Claude%20API")
        let youtube = try XCTUnwrap(WebURLBuilder.searchURL(engine: "youtube", query: "python & ml"))
        let item = URLComponents(url: youtube, resolvingAgainstBaseURL: false)?.queryItems?.first
        XCTAssertEqual(item?.name, "search_query")
        XCTAssertEqual(item?.value, "python & ml", "амперсанд не должен ломать запрос")
        XCTAssertNil(WebURLBuilder.searchURL(engine: "google", query: "  "))
        XCTAssertNil(WebURLBuilder.searchURL(engine: "bing", query: "x"))
    }

    func testKnownWebsites() {
        for site in ToolCatalog.knownWebsites {
            XCTAssertNotNil(WebURLBuilder.websiteURL(for: site), site)
        }
        XCTAssertEqual(WebURLBuilder.websiteURL(for: "github")?.absoluteString, "https://github.com")
        XCTAssertNil(WebURLBuilder.websiteURL(for: "evil"))
    }

    func testURLValidation() {
        XCTAssertNotNil(WebURLBuilder.validatedWebURL("https://developer.apple.com/documentation"))
        XCTAssertNotNil(WebURLBuilder.validatedWebURL("HTTP://example.com"))
        XCTAssertNil(WebURLBuilder.validatedWebURL("tel:123"))
        XCTAssertNil(WebURLBuilder.validatedWebURL("x-apple.systempreferences:com.apple.preference.security"))
    }

    // MARK: Громкость и байты

    func testVolumeMath() {
        XCTAssertEqual(VolumeMath.apply(delta: 20, to: 50), 70)
        XCTAssertEqual(VolumeMath.apply(delta: 20, to: 90), 100)
        XCTAssertEqual(VolumeMath.apply(delta: -30, to: 10), 0)
    }

    func testByteMath() {
        XCTAssertEqual(ByteMath.gigabytes(250_000_000_000), 250)
        XCTAssertEqual(ByteMath.usedPercent(available: 250, total: 1000), 75)
        XCTAssertEqual(ByteMath.usedPercent(available: 0, total: 0), 0)
    }

    // MARK: Поиск проектов

    func testProjectLocatorFindsXcodeProjectByLooseName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nova-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let project = root.appendingPathComponent("IdeaProjects/NOVA-AI", isDirectory: true)
        try fm.createDirectory(at: project.appendingPathComponent("NOVA.xcodeproj"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("IdeaProjects/nova-ai-old-notes"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("IdeaProjects/node_modules/NOVA-AI"), withIntermediateDirectories: true)

        let locator = ProjectLocator(searchPaths: ["~/IdeaProjects"], homeDirectory: root)
        let match = try XCTUnwrap(locator.find(projectNamed: "NOVA AI"))
        XCTAssertEqual(match.folderURL.lastPathComponent, "NOVA-AI")
        XCTAssertEqual(match.kind, .xcodeProject)
        XCTAssertEqual(match.openTargetURL.lastPathComponent, "NOVA.xcodeproj")
        XCTAssertFalse(locator.allMatches(projectNamed: "NOVA AI").contains { $0.folderURL.path.contains("node_modules") })
    }

    func testProjectLocatorPrefersWorkspaceAndPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nova-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let app = root.appendingPathComponent("Developer/MyApp", isDirectory: true)
        try fm.createDirectory(at: app.appendingPathComponent("MyApp.xcodeproj"), withIntermediateDirectories: true)
        try fm.createDirectory(at: app.appendingPathComponent("MyApp.xcworkspace"), withIntermediateDirectories: true)
        let package = root.appendingPathComponent("Developer/Kit", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.0".utf8).write(to: package.appendingPathComponent("Package.swift"))

        let locator = ProjectLocator(searchPaths: ["~/Developer"], homeDirectory: root)
        XCTAssertEqual(locator.find(projectNamed: "myapp")?.kind, .xcodeWorkspace)
        XCTAssertEqual(locator.find(projectNamed: "Kit")?.kind, .swiftPackage)
        XCTAssertNil(locator.find(projectNamed: "Nonexistent Project"))
    }

    // MARK: Настройки и ключ

    func testSettingsPersistAndSanitize() throws {
        let suite = "nova-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), AppSettings())

        var settings = AppSettings(language: .german, speechRate: 3, model: .sonnet)
        settings.contextTurnLimit = 1
        store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded.language, .german)
        XCTAssertEqual(loaded.model, .sonnet)
        XCTAssertEqual(loaded.speechRate, 1, "значения ограничиваются диапазоном")
        XCTAssertEqual(loaded.contextTurnLimit, 2)
        XCTAssertFalse(loaded.cloudProcessingConsent, "согласие по умолчанию выключено")
    }

    func testSettingsDecodeToleratesMissingFields() throws {
        let data = Data(#"{"language":"uk"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.language, .ukrainian)
        XCTAssertEqual(settings.model, .opus)
    }

    func testAPIKeyValidation() throws {
        XCTAssertEqual(try APIKeyValidator.normalized("  sk-ant-api03-abcdefghijklmnop \n"), "sk-ant-api03-abcdefghijklmnop")
        XCTAssertThrowsError(try APIKeyValidator.normalized("sk-abc"))
        XCTAssertThrowsError(try APIKeyValidator.normalized("sk-ant-has space inside-1234567"))
        XCTAssertEqual(APIKeyValidator.masked("sk-ant-api03-abcdefghWXYZ"), "sk-ant-…WXYZ")

        let store = InMemorySecretStore()
        XCTAssertThrowsError(try store.saveAPIKey("not-a-key"))
        try store.saveAPIKey("sk-ant-api03-abcdefghijklmnop")
        XCTAssertEqual(try store.readAPIKey(), "sk-ant-api03-abcdefghijklmnop")
        try store.deleteAPIKey()
        XCTAssertNil(try store.readAPIKey())
    }

    func testLanguagesHaveLocales() {
        XCTAssertEqual(SupportedLanguage.allCases.map(\.localeIdentifier), ["ru-RU", "uk-UA", "en-US", "de-DE"])
    }
}
