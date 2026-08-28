import XCTest
@testable import RundownCore

final class RunnerTests: XCTestCase {
    var t = Date(timeIntervalSince1970: 1_000_000)
    var runner: Runner!

    override func setUp() {
        t = Date(timeIntervalSince1970: 1_000_000)
        runner = Runner(now: { [unowned self] in self.t })
        runner.load(try! Parser.parse("5m intro, ? questions, 10m body, 5m outro"))
    }

    func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) }

    func testIdle() {
        XCTAssertEqual(runner.state, .idle)
        XCTAssertEqual(runner.totalRemaining, 1200)
        XCTAssertEqual(runner.drift, 0)
        XCTAssertEqual(runner.pace, .onTrack)
        XCTAssertEqual(runner.currentRemaining, 300)
        runner.next() // no-op when idle
        XCTAssertEqual(runner.index, 0)
    }

    func testCountdownAndOvertime() {
        runner.start()
        advance(100)
        XCTAssertEqual(runner.currentElapsed, 100)
        XCTAssertEqual(runner.currentRemaining, 200)
        XCTAssertEqual(runner.totalRemaining, 1100)
        XCTAssertEqual(runner.drift, 0)
        XCTAssertEqual(runner.progress!, 1.0 / 3.0, accuracy: 1e-9)
        advance(260) // 60s over
        XCTAssertEqual(runner.currentRemaining, -60)
        XCTAssertEqual(runner.drift, 60)
        XCTAssertEqual(runner.pace, .behind(60))
        XCTAssertEqual(runner.totalRemaining, 900)
        XCTAssertEqual(runner.progress, 1)
    }

    func testFinishingEarlyMakesYouAhead() {
        runner.start()
        advance(200)
        runner.next()
        XCTAssertEqual(runner.index, 1)
        XCTAssertEqual(runner.drift, -100)
        XCTAssertEqual(runner.pace, .ahead(100))
        XCTAssertEqual(runner.actualFor(0), 200)
    }

    func testStopwatchSegmentIsExcludedFromDriftAndRemaining() {
        runner.start()
        advance(300)
        runner.next() // into ? questions
        XCTAssertNil(runner.currentRemaining)
        XCTAssertNil(runner.progress)
        advance(600) // long Q&A
        XCTAssertEqual(runner.currentElapsed, 600)
        XCTAssertEqual(runner.drift, 0)
        XCTAssertEqual(runner.totalRemaining, 900)
        runner.next()
        XCTAssertEqual(runner.drift, 0)
        XCTAssertEqual(runner.index, 2)
    }

    func testPauseDoesNotAccumulate() {
        runner.start()
        advance(60)
        runner.pause()
        XCTAssertEqual(runner.state, .paused)
        advance(1000)
        XCTAssertEqual(runner.currentElapsed, 60)
        XCTAssertEqual(runner.drift, 0)
        runner.resume()
        advance(30)
        XCTAssertEqual(runner.currentElapsed, 90)
        runner.pause()
        runner.next() // advancing while paused stays paused
        XCTAssertEqual(runner.state, .paused)
        XCTAssertEqual(runner.index, 1)
        advance(100)
        XCTAssertEqual(runner.currentElapsed, 0)
        runner.togglePause()
        XCTAssertEqual(runner.state, .running)
    }

    func testPreviousKeepsAccumulating() {
        runner.start()
        advance(100)
        runner.next()
        advance(50)
        runner.previous()
        XCTAssertEqual(runner.index, 0)
        XCTAssertEqual(runner.actualFor(0), 100)
        XCTAssertEqual(runner.actualFor(1), 50)
        advance(100)
        XCTAssertEqual(runner.currentElapsed, 200)
        XCTAssertEqual(runner.drift, 0)
        runner.previous() // already at first segment
        XCTAssertEqual(runner.index, 0)
    }

    func testFinishAndReopen() {
        runner.start()
        runner.jump(to: 3)
        advance(400) // 100 over on outro
        runner.next()
        XCTAssertEqual(runner.state, .finished)
        XCTAssertEqual(runner.totalRemaining, 0)
        // intro (0 vs 300) = -300, body (0 vs 600) = -600, outro (400 vs 300) = +100
        XCTAssertEqual(runner.drift, -800)
        XCTAssertEqual(runner.totalElapsed, 400)
        XCTAssertTrue(runner.isDone(0))
        runner.next() // no-op
        XCTAssertEqual(runner.state, .finished)
        runner.previous()
        XCTAssertEqual(runner.state, .running)
        XCTAssertEqual(runner.index, 3)
        advance(10)
        XCTAssertEqual(runner.actualFor(3), 410)
        runner.reset()
        XCTAssertEqual(runner.state, .idle)
        XCTAssertEqual(runner.totalElapsed, 0)
        XCTAssertEqual(runner.index, 0)
    }

    func testProjectedAndPlannedEnd() {
        let start = t
        runner.start()
        XCTAssertEqual(runner.plannedEnd, start.addingTimeInterval(1200))
        advance(100)
        XCTAssertEqual(runner.projectedEnd, t.addingTimeInterval(1100))
        advance(300) // 100 over → projected end slips by 100
        XCTAssertEqual(runner.projectedEnd, start.addingTimeInterval(1300))
    }

    func testPaceTolerance() {
        runner.start()
        advance(310)
        XCTAssertEqual(runner.pace, .onTrack)
        advance(15)
        XCTAssertEqual(runner.pace, .behind(25))
    }

    func testLoadResets() {
        runner.start()
        advance(100)
        runner.load(try! Parser.parse("1m a"))
        XCTAssertEqual(runner.state, .idle)
        XCTAssertEqual(runner.actual, [0])
        XCTAssertEqual(runner.totalRemaining, 60)
    }
}
