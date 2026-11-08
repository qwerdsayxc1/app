import XCTest
@testable import NOVACore

final class ToolCatalogTests: XCTestCase {
    func testCatalogCoversEveryToolExactlyOnce() {
        let names = ToolCatalog.all.map(\.name)
        XCTAssertEqual(Set(names), Set(ToolName.allCases))
        XCTAssertEqual(names.count, ToolName.allCases.count, "дубликатов быть не должно")
    }

    func testEveryDefinitionIsStrictAndClosed() throws {
        for definition in ToolCatalog.all {
            let api = definition.apiDefinition()
            XCTAssertEqual(api["name"]?.stringValue, definition.name.rawValue)
            // strict не отправляем: API ограничивает число strict-инструментов (у нас их 32).
            XCTAssertNil(api["strict"], definition.name.rawValue)
            let schema = try XCTUnwrap(api["input_schema"])
            XCTAssertEqual(schema["type"]?.stringValue, "object")
            XCTAssertEqual(schema["additionalProperties"]?.boolValue, false)
            let properties = try XCTUnwrap(schema["properties"]?.objectValue)
            XCTAssertEqual(Set(properties.keys), Set(definition.parameters.map(\.name)))
            let required = try XCTUnwrap(schema["required"]?.arrayValue).compactMap(\.stringValue)
            XCTAssertEqual(Set(required), Set(definition.parameters.filter(\.isRequired).map(\.name)))
            XCTAssertFalse(definition.description.isEmpty)
        }
    }

    func testSchemasDoNotUseUnsupportedStrictKeywords() {
        // Числовые и длинные ограничения проверяются на клиенте, в схеме их нет.
        let text = ToolCatalog.apiTools().compactString()
        for keyword in ["\"minimum\"", "\"maximum\"", "\"minLength\"", "\"maxLength\"", "\"format\""] {
            XCTAssertFalse(text.contains(keyword), keyword)
        }
    }

    func testNoShellOrDestructiveToolsInWhitelist() {
        let forbidden = ["shell", "bash", "exec", "delete", "remove", "send_message", "purchase", "applescript"]
        for name in ToolName.allCases.map(\.rawValue) {
            for word in forbidden {
                XCTAssertFalse(name.contains(word), "\(name) содержит \(word)")
            }
        }
    }

    func testQuitRequiresConfirmation() {
        XCTAssertEqual(ToolCatalog.definition(for: .quitApplication).risk, .requiresConfirmation)
        XCTAssertEqual(ToolCatalog.definition(for: .openApplication).risk, .safe)
    }

    func testApiToolsOrderIsDeterministic() throws {
        XCTAssertEqual(try ToolCatalog.apiTools().encodedData(), try ToolCatalog.apiTools().encodedData())
    }
}
