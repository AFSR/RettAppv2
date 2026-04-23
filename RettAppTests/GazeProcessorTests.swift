import XCTest
@testable import RettApp

final class GazeProcessorTests: XCTestCase {

    func testNoHitReturnsNil() {
        let processor = GazeProcessor()
        let target = GameTarget(id: UUID(), position: CGPoint(x: 100, y: 100), diameter: 100)
        let result = processor.update(gazePoint: CGPoint(x: 500, y: 500), targets: [target])
        XCTAssertNil(result)
        XCTAssertNil(processor.currentTargetId)
    }

    func testDwellTriggersAfterDuration() async {
        let processor = GazeProcessor()
        processor.dwellDuration = 0.1
        let target = GameTarget(id: UUID(), position: CGPoint(x: 100, y: 100), diameter: 120)

        // Premier regard : démarre le dwell, retourne nil
        let first = processor.update(gazePoint: CGPoint(x: 105, y: 105), targets: [target])
        XCTAssertNil(first)
        XCTAssertEqual(processor.currentTargetId, target.id)

        try? await Task.sleep(nanoseconds: 150_000_000)

        // Deuxième regard après le dwell : doit déclencher
        let second = processor.update(gazePoint: CGPoint(x: 105, y: 105), targets: [target])
        XCTAssertEqual(second, target.id)
        // Reset après trigger
        XCTAssertNil(processor.currentTargetId)
    }

    func testSwitchingTargetResetsDwell() {
        let processor = GazeProcessor()
        let a = GameTarget(id: UUID(), position: CGPoint(x: 50, y: 50), diameter: 100)
        let b = GameTarget(id: UUID(), position: CGPoint(x: 400, y: 400), diameter: 100)

        _ = processor.update(gazePoint: a.position, targets: [a, b])
        XCTAssertEqual(processor.currentTargetId, a.id)
        _ = processor.update(gazePoint: b.position, targets: [a, b])
        XCTAssertEqual(processor.currentTargetId, b.id)
    }

    func testHourMinutePeriodClassification() {
        XCTAssertEqual(HourMinute(hour: 8, minute: 0).period, .morning)
        XCTAssertEqual(HourMinute(hour: 12, minute: 30).period, .noon)
        XCTAssertEqual(HourMinute(hour: 20, minute: 0).period, .evening)
        XCTAssertEqual(HourMinute(hour: 23, minute: 0).period, .other)
    }
}
