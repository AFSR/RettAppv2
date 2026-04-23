import XCTest
import SwiftData
@testable import AFSR

final class SeizureViewModelTests: XCTestCase {

    func testDurationFormatting() {
        XCTAssertEqual(SeizureEvent.formatDuration(0), "0 s")
        XCTAssertEqual(SeizureEvent.formatDuration(45), "45 s")
        XCTAssertEqual(SeizureEvent.formatDuration(60), "1 min 00 s")
        XCTAssertEqual(SeizureEvent.formatDuration(154), "2 min 34 s")
        XCTAssertEqual(SeizureEvent.formatDuration(3599), "59 min 59 s")
    }

    func testSeizureEventComputesDuration() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(90)
        let event = SeizureEvent(startTime: start, endTime: end)
        XCTAssertEqual(event.durationSeconds, 90)
        XCTAssertEqual(event.formattedDuration, "1 min 30 s")
    }

    func testPhaseTransitions() {
        let vm = SeizureTrackerViewModel()
        XCTAssertEqual(vm.phase, .idle)
        vm.start()
        if case .recording = vm.phase {} else { XCTFail("devrait être recording") }
        vm.stop()
        if case .qualifying = vm.phase {} else { XCTFail("devrait être qualifying") }
        vm.cancelQualification()
        XCTAssertEqual(vm.phase, .idle)
    }

    func testTimerAdvances() async {
        let vm = SeizureTrackerViewModel()
        vm.start()
        let initial = vm.currentDuration
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertGreaterThan(vm.currentDuration, initial)
        vm.cancelQualification()
    }
}
