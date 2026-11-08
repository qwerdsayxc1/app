import XCTest
@testable import NOVACore

final class ConfirmationParserTests: XCTestCase {
    func testPositiveAnswers() {
        for phrase in ["Да", "да, закрывай", "Так", "Yes", "ok", "Ja", "Подтверждаю"] {
            XCTAssertEqual(ConfirmationParser.parse(phrase), true, phrase)
        }
    }

    func testNegativeAnswers() {
        for phrase in ["Нет", "не надо", "Ні", "No", "cancel", "Nein", "отмена", "да нет"] {
            XCTAssertEqual(ConfirmationParser.parse(phrase), false, phrase)
        }
    }

    func testAmbiguousIsNil() {
        for phrase in ["", "   ", "открой YouTube", "может быть"] {
            XCTAssertNil(ConfirmationParser.parse(phrase), phrase)
        }
    }
}
