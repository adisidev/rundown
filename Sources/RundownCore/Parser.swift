import Foundation

/// Something to cover during a segment, written as a `- [ ]` line under it. Ids are unique across the routine.
public struct ChecklistItem: Equatable, Identifiable {
    public let id: Int
    public var text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

public struct Segment: Equatable, Identifiable {
    public let id: Int
    public var name: String
    /// Planned duration in seconds; nil means a stopwatch segment (open-ended).
    public var planned: TimeInterval?
    public var items: [ChecklistItem]

    public init(id: Int, name: String, planned: TimeInterval?, items: [ChecklistItem] = []) {
        self.id = id
        self.name = name
        self.planned = planned
        self.items = items
    }

    public var isStopwatch: Bool { planned == nil }
}

public struct Routine: Equatable {
    public var title: String?
    public var segments: [Segment]

    public init(title: String? = nil, segments: [Segment]) {
        self.title = title
        self.segments = segments
    }

    public var plannedTotal: TimeInterval { segments.compactMap(\.planned).reduce(0, +) }
    public var items: [ChecklistItem] { segments.flatMap(\.items) }
}

public enum ParseError: Error, LocalizedError, Equatable {
    case noSegments

    public var errorDescription: String? {
        switch self {
        case .noSegments: return "No segments found. Write something like `5m intro, 10m demo, ? questions`."
        }
    }
}

/// Turns a markdown-ish routine description into a `Routine`.
///
/// Rules:
/// - The first `# Heading` becomes the title. Other heading lines are ignored.
/// - Blank lines and lines starting with `>`, `<!--` or `---` are ignored.
/// - List bullets (`- `, `* `, `+ `, `1. `, `1)`) are stripped.
/// - A checkbox line (`- [ ] UEN number`, `[x]` too) is a checklist item of the segment above it, taken verbatim
///   (commas allowed). Checkboxes before any segment go into an open-ended "Checklist" segment.
/// - Each remaining line is split on commas; every piece is one segment.
/// - A segment is `<duration> <name>` or `<name> <duration>`. Duration: `5m`, `90s`, `1h30m`, `2:30`, `1:05:00`.
///   A bare integer prefix (`5 intro`) means minutes. `?`, `~` or `∞` — or no duration at all — makes a stopwatch segment.
public enum Parser {
    public static func parse(_ text: String) throws -> Routine {
        var title: String?
        var segments: [Segment] = []
        var itemCount = 0

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix(">") || line.hasPrefix("<!--") || line.hasPrefix("---") { continue }
            if line.hasPrefix("#") {
                if title == nil, line.hasPrefix("# ") {
                    title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            line = stripBullet(line)
            if let item = checkboxText(line) {
                if item.isEmpty { continue }
                if segments.isEmpty { segments.append(Segment(id: 0, name: "Checklist", planned: nil)) }
                segments[segments.count - 1].items.append(ChecklistItem(id: itemCount, text: item))
                itemCount += 1
                continue
            }
            if line.isEmpty { continue }

            for piece in line.split(separator: ",") {
                let p = piece.trimmingCharacters(in: .whitespaces)
                if p.isEmpty { continue }
                segments.append(parseSegment(p, index: segments.count))
            }
        }

        guard !segments.isEmpty else { throw ParseError.noSegments }
        return Routine(title: title, segments: segments)
    }

    static func stripBullet(_ line: String) -> String {
        var s = Substring(line)
        // "- ", "* ", "+ "
        if let f = s.first, "-*+".contains(f), s.dropFirst().first?.isWhitespace == true {
            s = s.dropFirst()
        } else {
            // "1. " / "1) "
            let digits = s.prefix(while: \.isNumber)
            if !digits.isEmpty {
                let rest = s.dropFirst(digits.count)
                if let f = rest.first, ".)".contains(f), rest.dropFirst().first?.isWhitespace == true {
                    s = rest.dropFirst()
                }
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// The item text if `line` (bullet already stripped) starts with a checkbox, else nil.
    static func checkboxText(_ line: String) -> String? {
        for box in ["[ ]", "[x]", "[X]"] where line.hasPrefix(box) {
            return String(line.dropFirst(box.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    enum DurationToken: Equatable {
        case timed(TimeInterval)
        case stopwatch
    }

    /// Recognises a duration token, optionally wrapped in `()` or `[]`.
    static func durationToken(_ token: String, allowBareMinutes: Bool) -> DurationToken? {
        let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]:-–—"))
        if Duration.stopwatchMarkers.contains(t) { return .stopwatch }
        if let d = Duration.parse(t) { return .timed(d) }
        if allowBareMinutes, !t.isEmpty, t.allSatisfy(\.isNumber), let n = Double(t) { return .timed(n * 60) }
        return nil
    }

    static func parseSegment(_ piece: String, index: Int) -> Segment {
        var tokens = piece.split(whereSeparator: \.isWhitespace).map(String.init)
        var planned: TimeInterval?

        if let first = tokens.first, let tok = durationToken(first, allowBareMinutes: true) {
            tokens.removeFirst()
            if case .timed(let d) = tok { planned = d }
        } else if let last = tokens.last, let tok = durationToken(last, allowBareMinutes: false) {
            tokens.removeLast()
            if case .timed(let d) = tok { planned = d }
        }

        var name = tokens.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·"))
        // Unwrap simple markdown emphasis.
        for wrap in ["**", "__", "*", "_", "`"] where name.count > wrap.count * 2 && name.hasPrefix(wrap) && name.hasSuffix(wrap) {
            name = String(name.dropFirst(wrap.count).dropLast(wrap.count))
        }
        if name.isEmpty { name = "Segment \(index + 1)" }
        return Segment(id: index, name: name, planned: planned)
    }
}
