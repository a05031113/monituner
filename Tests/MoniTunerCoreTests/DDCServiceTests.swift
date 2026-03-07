import XCTest
@testable import MoniTunerCore

final class DDCServiceTests: XCTestCase {

    func testParseDisplayList() {
        let output = """
        [1] BenQ BL3290QT (B24F0E3A-9C4F-4EC8-BC65-24B731598C02)
        [2] (null) (37D8832A-2D66-02CA-B9F7-8F30A301B230)
        [3] VP32UQ (2D7B40B8-405F-4FF1-972B-B9930425D56E)
        """
        let displays = DDCService.parseDisplayList(output)
        XCTAssertEqual(displays.count, 2, "should skip (null) entries")
        XCTAssertEqual(displays["BenQ BL3290QT"], 1)
        XCTAssertEqual(displays["VP32UQ"], 3)
    }

    func testParseDisplayListEmpty() {
        let displays = DDCService.parseDisplayList("")
        XCTAssertTrue(displays.isEmpty)
    }

    func testParseDisplayListNoValidEntries() {
        let output = "[1] (null) (ABC-123)"
        let displays = DDCService.parseDisplayList(output)
        XCTAssertTrue(displays.isEmpty)
    }

    func testParseLuminanceValue() {
        XCTAssertEqual(DDCService.parseIntOutput("60\n"), 60)
        XCTAssertEqual(DDCService.parseIntOutput("  42  \n"), 42)
        XCTAssertNil(DDCService.parseIntOutput("error"))
        XCTAssertNil(DDCService.parseIntOutput(""))
    }

    func testParseZeroValue() {
        XCTAssertEqual(DDCService.parseIntOutput("0"), 0)
    }
}
