import Foundation

/// Parsing and formatting of durations as they appear in routine files.
public enum Duration {
    /// Tokens that mark a segment as a stopwatch (open-ended, no planned duration).
    public static let stopwatchMarkers: Set<String> = ["?", "~", "∞"]

    /// Parses `1h30m`, `5m`, `90s`, `2m30s`, `2:30`, `1:05:00`. Returns nil if the string is not a duration.
    /// Bare integers are NOT accepted here; the parser handles those (prefix-only, minutes).
    public static func parse(_ raw: String) -> TimeInterval? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }

        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count),
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
            else { return nil }
            let n = parts.map { Double($0)! }
            return parts.count == 2 ? n[0] * 60 + n[1] : n[0] * 3600 + n[1] * 60 + n[2]
        }

        var total: TimeInterval = 0
        var number = ""
        var sawUnit = false
        for ch in s {
            if ch.isNumber || ch == "." {
                number.append(ch)
            } else {
                guard let n = Double(number) else { return nil }
                switch ch {
                case "h": total += n * 3600
                case "m": total += n * 60
                case "s": total += n
                default: return nil
                }
                number = ""
                sawUnit = true
            }
        }
        guard number.isEmpty, sawUnit else { return nil }
        return total
    }

    /// `m:ss` under an hour, `h:mm:ss` otherwise. Negative values get a leading `-`; `signed` adds `+` to non-negative ones.
    public static func format(_ t: TimeInterval, signed: Bool = false) -> String {
        let total = Int(abs(t).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let body = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        if t < 0 && total > 0 { return "-" + body }
        return signed ? "+" + body : body
    }

    /// Short human form for plans: `5m`, `1h30m`, `90s`.
    public static func short(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var out = ""
        if h > 0 { out += "\(h)h" }
        if m > 0 { out += "\(m)m" }
        if s > 0 || out.isEmpty { out += "\(s)s" }
        return out
    }
}
