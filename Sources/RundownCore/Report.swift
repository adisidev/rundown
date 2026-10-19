import Foundation

/// Markdown written out after a run: what was missed first (the follow-up list), then every segment with its time and items.
public enum Report {
    /// Unticked items grouped by segment, or nil when everything was ticked.
    public static func missed(_ runner: Runner) -> String? {
        var out: [String] = []
        for (i, seg) in runner.segments.enumerated() {
            let open = runner.openItems(in: i)
            guard !open.isEmpty else { continue }
            out.append("**\(seg.name)**")
            out += open.map { "- [ ] \($0.text)" }
            out.append("")
        }
        return out.isEmpty ? nil : out.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    public static func markdown(_ runner: Runner, title: String) -> String {
        let started = runner.startedAt ?? runner.now()
        var out = ["# \(title) · \(started.formatted(date: .abbreviated, time: .shortened))", ""]
        var summary = "took \(Duration.format(runner.totalElapsed))"
        if runner.plannedTotal > 0 { summary += " of \(Duration.format(runner.plannedTotal)) planned" }
        if runner.hasChecklist { summary += " · \(runner.checkedCount)/\(runner.itemCount) covered" }
        out += [summary, ""]

        if let missed = missed(runner) {
            out += ["## Missed", "", missed, ""]
        } else if runner.hasChecklist {
            out += ["Everything on the checklist was covered.", ""]
        }

        out += ["## Segments", ""]
        for (i, seg) in runner.segments.enumerated() {
            var line = "- \(seg.name) · \(Duration.format(runner.actualFor(i)))"
            if let p = runner.planned(i) { line += " / \(Duration.format(p))" }
            out.append(line)
            for item in seg.items {
                out.append("  - [\(runner.isChecked(item) ? "x" : " ")] \(item.text)")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}
