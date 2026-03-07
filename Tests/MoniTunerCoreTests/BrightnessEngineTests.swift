import XCTest
@testable import MoniTunerCore

final class BrightnessEngineTests: XCTestCase {

    // MARK: - luxToBrightness

    func testDarkRoom() {
        let brightness = BrightnessEngine.luxToBrightness(0)
        XCTAssertEqual(brightness, 5, accuracy: 2, "0 lux → ~5%")
    }

    func testDimRoom() {
        let brightness = BrightnessEngine.luxToBrightness(50)
        XCTAssertEqual(brightness, 20, accuracy: 5, "50 lux → ~20%")
    }

    func testNormalIndoor() {
        let brightness = BrightnessEngine.luxToBrightness(200)
        XCTAssertEqual(brightness, 40, accuracy: 5, "200 lux → ~40%")
    }

    func testBrightIndoor() {
        let brightness = BrightnessEngine.luxToBrightness(500)
        XCTAssertEqual(brightness, 60, accuracy: 5, "500 lux → ~60%")
    }

    func testNearWindow() {
        let brightness = BrightnessEngine.luxToBrightness(1000)
        XCTAssertEqual(brightness, 80, accuracy: 5, "1000 lux → ~80%")
    }

    func testOutdoor() {
        let brightness = BrightnessEngine.luxToBrightness(5000)
        XCTAssertEqual(brightness, 100, accuracy: 2, "5000 lux → 100%")
    }

    func testNegativeLux() {
        let brightness = BrightnessEngine.luxToBrightness(-10)
        XCTAssertEqual(brightness, 5, accuracy: 2, "negative lux clamped to min")
    }

    func testMonotonicallyIncreasing() {
        var prev: Double = -1
        for lux in stride(from: 0.0, through: 5000, by: 50) {
            let b = BrightnessEngine.luxToBrightness(lux)
            XCTAssertGreaterThanOrEqual(b, prev, "curve must be monotonically increasing at lux=\(lux)")
            prev = b
        }
    }

    // MARK: - clampBrightness

    func testClampAbove100() {
        XCTAssertEqual(BrightnessEngine.clampBrightness(110), 100)
    }

    func testClampBelow0() {
        XCTAssertEqual(BrightnessEngine.clampBrightness(-5), 0)
    }

    func testClampNormal() {
        XCTAssertEqual(BrightnessEngine.clampBrightness(50), 50)
    }

    // MARK: - stepBrightness

    func testStepUp() {
        let result = BrightnessEngine.stepBrightness(current: 50, isUp: true)
        XCTAssertEqual(result, 56.25, accuracy: 0.1)
    }

    func testStepDown() {
        let result = BrightnessEngine.stepBrightness(current: 50, isUp: false)
        XCTAssertEqual(result, 43.75, accuracy: 0.1)
    }

    func testStepUpClampsAt100() {
        let result = BrightnessEngine.stepBrightness(current: 97, isUp: true)
        XCTAssertEqual(result, 100, accuracy: 0.1)
    }

    func testStepDownClampsAt0() {
        let result = BrightnessEngine.stepBrightness(current: 3, isUp: false)
        XCTAssertEqual(result, 0, accuracy: 0.1)
    }

    // MARK: - brightnessToChiclets

    func testChiclets0() {
        XCTAssertEqual(BrightnessEngine.brightnessToChiclets(0), 0)
    }

    func testChiclets50() {
        XCTAssertEqual(BrightnessEngine.brightnessToChiclets(50), 8)
    }

    func testChiclets100() {
        XCTAssertEqual(BrightnessEngine.brightnessToChiclets(100), 16)
    }
}
