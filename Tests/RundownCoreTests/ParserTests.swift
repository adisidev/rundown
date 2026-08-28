import XCTest
@testable import RundownCore

final class ParserTests: XCTestCase {
    func testOneLiner() throws {
        let r = try Parser.parse("5m intro, 10m motivation, 20m results, 5m conclusion")
        XCTAssertNil(r.title)
        XCTAssertEqual(r.segments.map(\.name), ["intro", "motivation", "results", "conclusion"])
        XCTAssertEqual(r.segments.map(\.planned), [300, 600, 1200, 300])
        XCTAssertEqual(r.plannedTotal, 2400)
    }

    func testMultiLineListWithTitleAndStopwatches() throws {
        let text = """
        # My talk

        > a comment
        <!-- html comment -->
        ## ignored heading
        - 5m intro
        * intro demo 2:30
        + 1h30m long section
        1. 5 bare minutes
        2) ? questions
        - [ ] ~ open floor
        - no duration at all
        - 2m30s **bold name**
        ---
        """
        let r = try Parser.parse(text)
        XCTAssertEqual(r.title, "My talk")
        XCTAssertEqual(r.segments.map(\.name), [
            "intro", "intro demo", "long section", "bare minutes", "questions", "open floor", "no duration at all", "bold name",
        ])
        XCTAssertEqual(r.segments.map(\.planned), [300, 150, 5400, 300, nil, nil, nil, 150])
        XCTAssertEqual(r.segments.map(\.id), Array(0..<8))
    }

    func testMixedLinesAndCommas() throws {
        let r = try Parser.parse("5m a, 10m b\n15m c\n")
        XCTAssertEqual(r.segments.map(\.planned), [300, 600, 900])
    }

    func testBareIntegerSuffixIsNotADuration() throws {
        let r = try Parser.parse("top 10")
        XCTAssertEqual(r.segments[0].name, "top 10")
        XCTAssertNil(r.segments[0].planned)
    }

    func testSeparatorsAndParens() throws {
        let r = try Parser.parse("5m - intro, 10m: body, outro (3m)")
        XCTAssertEqual(r.segments.map(\.name), ["intro", "body", "outro"])
        XCTAssertEqual(r.segments.map(\.planned), [300, 600, 180])
    }

    func testEmptyNameGetsDefault() throws {
        let r = try Parser.parse("5m, 10m")
        XCTAssertEqual(r.segments.map(\.name), ["Segment 1", "Segment 2"])
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try Parser.parse("# only a title\n\n> nothing"))
    }

    func testDurationParse() {
        XCTAssertEqual(Duration.parse("5m"), 300)
        XCTAssertEqual(Duration.parse("90s"), 90)
        XCTAssertEqual(Duration.parse("1h"), 3600)
        XCTAssertEqual(Duration.parse("1H30M"), 5400)
        XCTAssertEqual(Duration.parse("2m30s"), 150)
        XCTAssertEqual(Duration.parse("1h5m10s"), 3910)
        XCTAssertEqual(Duration.parse("2:30"), 150)
        XCTAssertEqual(Duration.parse("1:05:00"), 3900)
        XCTAssertEqual(Duration.parse("0.5h"), 1800)
        XCTAssertNil(Duration.parse("5"))
        XCTAssertNil(Duration.parse("m"))
        XCTAssertNil(Duration.parse("5x"))
        XCTAssertNil(Duration.parse("intro"))
        XCTAssertNil(Duration.parse("1:2:3:4"))
    }

    func testDurationFormat() {
        XCTAssertEqual(Duration.format(0), "0:00")
        XCTAssertEqual(Duration.format(65), "1:05")
        XCTAssertEqual(Duration.format(3661), "1:01:01")
        XCTAssertEqual(Duration.format(-83), "-1:23")
        XCTAssertEqual(Duration.format(83, signed: true), "+1:23")
        XCTAssertEqual(Duration.format(-0.2), "0:00")
        XCTAssertEqual(Duration.short(300), "5m")
        XCTAssertEqual(Duration.short(5400), "1h30m")
        XCTAssertEqual(Duration.short(90), "1m30s")
        XCTAssertEqual(Duration.short(0), "0s")
    }
}
