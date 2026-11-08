import XCTest
@testable import NOVACore

final class ToolSamplesTests: XCTestCase {
    /// Каждый пример на экране «Проверка» должен проходить строгую валидацию.
    func testEverySampleIsValid() {
        let validator = ToolArgumentValidator()
        for tool in ToolName.allCases {
            XCTAssertNoThrow(try validator.validate(toolName: tool.rawValue, input: ToolSamples.sample(for: tool)), tool.rawValue)
        }
    }

    func testSelfTestSequenceIsValidAndSafe() {
        let validator = ToolArgumentValidator()
        let unsafe: Set<String> = ["quit_application", "sleep_display", "hide_application", "set_dark_mode", "create_reminder", "media_control", "browser_tab"]
        XCTAssertFalse(ToolSamples.selfTestSequence.isEmpty)
        for call in ToolSamples.selfTestSequence {
            XCTAssertNoThrow(try validator.validate(toolName: call.name, input: call.input), call.name)
            XCTAssertFalse(unsafe.contains(call.name), "\(call.name) не должен запускаться без человека")
        }
    }
}
