import XCTest
@testable import NOVACore

final class ToolValidationTests: XCTestCase {
    private let validator = ToolArgumentValidator()

    // MARK: Белый список

    func testUnknownToolIsRejected() {
        XCTAssertThrowsError(try validator.validate(toolName: "run_shell", input: ["command": "rm -rf /"])) { error in
            XCTAssertEqual(error as? ToolValidationError, .unknownTool("run_shell"))
        }
    }

    func testToolNameIsCaseSensitive() {
        XCTAssertThrowsError(try validator.validate(toolName: "Open_Application", input: ["name": "Safari"]))
    }

    // MARK: Структура

    func testValidCallPasses() throws {
        let args = try validator.validate(toolName: "open_application", input: ["name": "  Telegram "])
        XCTAssertEqual(args.tool, .openApplication)
        XCTAssertEqual(args.string("name"), "Telegram", "строки обрезаются по краям")
    }

    func testMissingRequiredArgument() {
        XCTAssertThrowsError(try validator.validate(toolName: "open_application", input: [:])) { error in
            XCTAssertEqual(error as? ToolValidationError, .missingArgument("name"))
        }
    }

    func testNullRequiredArgumentCountsAsMissing() {
        XCTAssertThrowsError(try validator.validate(toolName: "set_mute", input: ["muted": nil])) { error in
            XCTAssertEqual(error as? ToolValidationError, .missingArgument("muted"))
        }
    }

    func testUnexpectedArgumentIsRejected() {
        XCTAssertThrowsError(try validator.validate(toolName: "get_battery_status", input: ["verbose": true])) { error in
            XCTAssertEqual(error as? ToolValidationError, .unexpectedArgument("verbose"))
        }
    }

    func testNonObjectInputIsRejected() {
        XCTAssertThrowsError(try validator.validate(toolName: "open_application", input: "Safari")) { error in
            XCTAssertEqual(error as? ToolValidationError, .argumentsNotObject)
        }
    }

    func testNullInputAllowedForParameterlessTool() throws {
        let args = try validator.validate(toolName: "list_running_applications", input: .null)
        XCTAssertTrue(args.values.isEmpty)
    }

    func testOptionalArgumentMayBeOmitted() throws {
        let args = try validator.validate(toolName: "list_windows", input: [:])
        XCTAssertNil(args.string("application"))
    }

    // MARK: Типы

    func testTypeMismatchString() {
        XCTAssertThrowsError(try validator.validate(toolName: "open_application", input: ["name": 42])) { error in
            XCTAssertEqual(error as? ToolValidationError, .typeMismatch(argument: "name", expected: "string", actual: "number"))
        }
    }

    func testIntegerMustBeWhole() {
        XCTAssertThrowsError(try validator.validate(toolName: "set_volume", input: ["level": 20.5])) { error in
            XCTAssertEqual(error as? ToolValidationError, .typeMismatch(argument: "level", expected: "integer", actual: "number"))
        }
    }

    func testIntegerAsStringIsRejected() {
        XCTAssertThrowsError(try validator.validate(toolName: "set_volume", input: ["level": "20"]))
    }

    func testBooleanTypeMismatch() {
        XCTAssertThrowsError(try validator.validate(toolName: "set_mute", input: ["muted": "yes"])) { error in
            XCTAssertEqual(error as? ToolValidationError, .typeMismatch(argument: "muted", expected: "boolean", actual: "string"))
        }
    }

    // MARK: Ограничения

    func testIntegerRange() throws {
        XCTAssertNoThrow(try validator.validate(toolName: "set_volume", input: ["level": 0]))
        XCTAssertNoThrow(try validator.validate(toolName: "set_volume", input: ["level": 100]))
        XCTAssertThrowsError(try validator.validate(toolName: "set_volume", input: ["level": 101])) { error in
            XCTAssertEqual(error as? ToolValidationError, .outOfRange(argument: "level", value: 101, min: 0, max: 100))
        }
        XCTAssertThrowsError(try validator.validate(toolName: "change_volume", input: ["delta": -150]))
        XCTAssertEqual(try validator.validate(toolName: "change_volume", input: ["delta": -20]).int("delta"), -20)
    }

    func testEnumValuesAreNormalizedAndChecked() throws {
        let args = try validator.validate(toolName: "web_search", input: ["engine": "YouTube", "query": "python"])
        XCTAssertEqual(args.string("engine"), "youtube")
        XCTAssertThrowsError(try validator.validate(toolName: "web_search", input: ["engine": "bing", "query": "x"])) { error in
            guard case .valueNotAllowed(let argument, _, _)? = error as? ToolValidationError else {
                return XCTFail("ожидалась valueNotAllowed")
            }
            XCTAssertEqual(argument, "engine")
        }
    }

    func testEmptyAndWhitespaceStringsRejected() {
        XCTAssertThrowsError(try validator.validate(toolName: "open_application", input: ["name": "   "])) { error in
            XCTAssertEqual(error as? ToolValidationError, .emptyString(argument: "name"))
        }
    }

    func testTooLongStringRejected() {
        let long = String(repeating: "a", count: 81)
        XCTAssertThrowsError(try validator.validate(toolName: "open_application", input: ["name": .string(long)])) { error in
            XCTAssertEqual(error as? ToolValidationError, .stringTooLong(argument: "name", maxLength: 80))
        }
    }

    func testControlCharactersRejected() {
        XCTAssertThrowsError(try validator.validate(toolName: "open_application", input: ["name": "Safari\u{0007}"]))
        XCTAssertThrowsError(try validator.validate(toolName: "show_notification", input: ["title": "Hi", "message": "abc\u{202E}cba"]))
        XCTAssertNoThrow(try validator.validate(toolName: "show_notification", input: ["title": "Готово", "message": "Строка 1\nСтрока 2"]))
    }

    func testURLMustBeHTTP() {
        XCTAssertNoThrow(try validator.validate(toolName: "open_url", input: ["url": "https://www.apple.com"]))
        for bad in ["file:///etc/passwd", "javascript:alert(1)", "ftp://example.com", "https://", "www.apple.com", "https://user:pass@evil.com"] {
            XCTAssertThrowsError(try validator.validate(toolName: "open_url", input: ["url": .string(bad)]), bad) { error in
                XCTAssertEqual(error as? ToolValidationError, .invalidURL(argument: "url"), bad)
            }
        }
    }
}
