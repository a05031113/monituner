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

    // MARK: - DDC ↔ Percent Conversion

    func testDDCToPercent_max100() {
        XCTAssertEqual(DDCService.ddcToPercent(raw: 50, max: 100), 50)
        XCTAssertEqual(DDCService.ddcToPercent(raw: 0, max: 100), 0)
        XCTAssertEqual(DDCService.ddcToPercent(raw: 100, max: 100), 100)
    }

    func testDDCToPercent_max50() {
        // BenQ BL3290QT has max 50
        XCTAssertEqual(DDCService.ddcToPercent(raw: 25, max: 50), 50)
        XCTAssertEqual(DDCService.ddcToPercent(raw: 50, max: 50), 100)
        XCTAssertEqual(DDCService.ddcToPercent(raw: 0, max: 50), 0)
    }

    func testDDCToPercent_max110() {
        // VP32UQ has max 110
        XCTAssertEqual(DDCService.ddcToPercent(raw: 110, max: 110), 100)
        XCTAssertEqual(DDCService.ddcToPercent(raw: 55, max: 110), 50)
        XCTAssertEqual(DDCService.ddcToPercent(raw: 0, max: 110), 0)
    }

    func testPercentToDDC_max50() {
        XCTAssertEqual(DDCService.percentToDDC(percent: 100, max: 50), 50)
        XCTAssertEqual(DDCService.percentToDDC(percent: 50, max: 50), 25)
        XCTAssertEqual(DDCService.percentToDDC(percent: 0, max: 50), 0)
    }

    func testPercentToDDC_max110() {
        XCTAssertEqual(DDCService.percentToDDC(percent: 100, max: 110), 110)
        XCTAssertEqual(DDCService.percentToDDC(percent: 50, max: 110), 55)
        XCTAssertEqual(DDCService.percentToDDC(percent: 0, max: 110), 0)
    }

    func testDDCToPercent_maxZero() {
        XCTAssertEqual(DDCService.ddcToPercent(raw: 50, max: 0), 0)
    }

    func testRoundTrip() {
        // percent → DDC → percent should be stable
        for max in [50, 100, 110] {
            for pct in stride(from: 0, through: 100, by: 10) {
                let raw = DDCService.percentToDDC(percent: pct, max: max)
                let back = DDCService.ddcToPercent(raw: raw, max: max)
                XCTAssertEqual(back, pct, "roundtrip failed for \(pct)% with max=\(max)")
            }
        }
    }
}
