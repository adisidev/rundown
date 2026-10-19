import XCTest
@testable import RundownCore

final class ChecklistTests: XCTestCase {
    var t = Date(timeIntervalSince1970: 1_000_000)
    var runner: Runner!

    let playbook = """
    # Grant intake

    - [ ] who is applying
    - 5m eligibility
      - [ ] registered entity, UEN
      - [x] past grants
    - 15m budget
      - [ ] total ask
      - [ ] itemised lines, with quotes
    - ? anything else
    """

    override func setUp() {
        t = Date(timeIntervalSince1970: 1_000_000)
        runner = Runner(now: { [unowned self] in self.t })
        runner.load(try! Parser.parse(playbook))
    }

    func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) }

    func testParsesItemsUnderSegments() throws {
        let r = try Parser.parse(playbook)
        XCTAssertEqual(r.segments.map(\.name), ["Checklist", "eligibility", "budget", "anything else"])
        XCTAssertEqual(r.segments.map(\.planned), [nil, 300, 900, nil])
        XCTAssertEqual(r.segments[1].items.map(\.text), ["registered entity, UEN", "past grants"])
        XCTAssertEqual(r.segments[2].items.map(\.text), ["total ask", "itemised lines, with quotes"])
        XCTAssertEqual(r.items.map(\.id), Array(0..<5))
    }

    func testOnlyCheckboxesIsAChecklist() throws {
        let r = try Parser.parse("- [ ] a\n- [ ] b")
        XCTAssertEqual(r.segments.count, 1)
        XCTAssertEqual(r.segments[0].items.count, 2)
    }

    func testTickingAndMissed() {
        runner.start()
        XCTAssertEqual(runner.checkNext()?.text, "who is applying")
        XCTAssertNil(runner.checkNext())
        runner.next() // eligibility
        runner.checkNext()
        runner.next() // budget: eligibility left with one open
        XCTAssertEqual(runner.missedCount, 1)
        runner.toggle(runner.segments[2].items[1])
        runner.next(); runner.next() // finish
        XCTAssertEqual(runner.state, .finished)
        XCTAssertEqual(runner.missedCount, 2)
        XCTAssertEqual(Report.missed(runner), "**eligibility**\n- [ ] past grants\n\n**budget**\n- [ ] total ask")
        runner.reset()
        XCTAssertEqual(runner.checkedCount, 0)
    }

    func testCountUpIgnoresDurations() {
        runner.countUp = true
        XCTAssertTrue(runner.isUntimed)
        runner.start()
        runner.next()
        advance(600)
        XCTAssertNil(runner.currentRemaining)
        XCTAssertEqual(runner.drift, 0)
        XCTAssertEqual(runner.totalRemaining, 0)
        XCTAssertEqual(runner.totalElapsed, 600)
        runner.countUp = false
        XCTAssertEqual(runner.currentRemaining, -300)
    }

    func testReportListsEverySegment() {
        runner.start()
        advance(90)
        runner.checkNext()
        runner.next(); runner.next(); runner.next(); runner.next()
        let md = Report.markdown(runner, title: "Grant intake")
        XCTAssertTrue(md.contains("1/5 covered"))
        XCTAssertTrue(md.contains("## Missed"))
        XCTAssertTrue(md.contains("- Checklist · 1:30"))
        XCTAssertTrue(md.contains("  - [x] who is applying"))
    }
}
