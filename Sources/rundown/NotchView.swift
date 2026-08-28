import SwiftUI
import RundownCore

struct NotchView: View {
    @ObservedObject var runner: Runner
    @ObservedObject var ticker: Ticker
    @ObservedObject var state: PanelState
    let actions: PanelActions

    private var g: NotchGeometry { state.geometry }
    private var expanded: Bool { state.expanded }

    var body: some View {
        let width = expanded ? g.expandedWidth : g.compactWidth
        let height = expanded ? g.expandedHeight : g.compactHeight
        let _ = ticker.now // subscribe to ticks
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 20 : 12, bottomTrailingRadius: expanded ? 20 : 12)
                .fill(.black)
            VStack(spacing: 0) {
                compactRow(width: width)
                    .frame(height: g.compactHeight)
                if expanded {
                    expandedBody
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .frame(width: width, height: height)
        .animation(.spring(duration: 0.26, bounce: 0.08), value: expanded)
        .frame(width: g.expandedWidth, height: g.expandedHeight, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Compact row (visible in both states)

    private func compactRow(width: CGFloat) -> some View {
        let wing = (width - g.notchWidth) / 2
        return HStack(spacing: 0) {
            leftWing.frame(width: wing)
            if g.hasNotch {
                Color.clear.frame(width: g.notchWidth)
            } else {
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 14)
            }
            rightWing.frame(width: wing)
        }
        .opacity(runner.state == .paused ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { actions.primary() }
        .contextMenu {
            Button("Open Routine…") { actions.open() }
            Button(runner.state == .running ? "Pause" : "Start / Resume") { actions.playPause() }
                .disabled(!runner.hasRoutine || runner.state == .finished)
            Button("Reset") { runner.reset() }.disabled(!runner.hasStarted)
            Divider()
            Button("Quit rundown") { actions.quit() }
        }
    }

    private var leftWing: some View {
        HStack(spacing: 8) {
            if runner.state == .paused {
                Image(systemName: "pause.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(segmentLabel)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(segmentTime)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(segmentTimeColor)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
    }

    private var rightWing: some View {
        HStack(spacing: 6) {
            Text(totalLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            paceChip
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
    }

    private var segmentLabel: String {
        switch runner.state {
        case .idle: return runner.current?.name ?? "rundown"
        case .finished: return "done"
        case .running, .paused: return runner.current?.name ?? ""
        }
    }

    private var segmentTime: String {
        switch runner.state {
        case .idle:
            guard runner.hasRoutine else { return "" }
            return runner.current?.planned.map { Duration.format($0) } ?? "⏱"
        case .finished:
            return Duration.format(runner.totalElapsed)
        case .running, .paused:
            if let r = runner.currentRemaining {
                return r < 0 ? Duration.format(-r, signed: true) : Duration.format(r)
            }
            return "⏱ " + Duration.format(runner.currentElapsed)
        }
    }

    private var segmentTimeColor: Color {
        if let r = runner.currentRemaining, runner.hasStarted, runner.state != .finished {
            if r < 0 { return .red }
            if r < 30 { return .orange }
        }
        return .white
    }

    private var totalLabel: String {
        switch runner.state {
        case .idle: return runner.hasRoutine ? Duration.format(runner.plannedTotal) : "open a routine"
        case .finished: return Duration.format(runner.drift, signed: true)
        case .running, .paused: return Duration.format(runner.totalRemaining)
        }
    }

    @ViewBuilder private var paceChip: some View {
        if runner.hasStarted, runner.state != .finished {
            switch runner.pace {
            case .onTrack:
                Circle().fill(.green).frame(width: 7, height: 7)
            case .behind(let by):
                Label(Duration.format(by), systemImage: "arrowtriangle.up.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.red)
            case .ahead(let by):
                Label(Duration.format(by), systemImage: "arrowtriangle.down.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
        } else if runner.state == .idle, runner.hasRoutine {
            Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(.secondary)
        } else if runner.state == .finished {
            Text(runner.drift > 0 ? "over" : "under").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: Expanded body

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(runner.routine?.title ?? state.fileName ?? "rundown")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(paceSentence)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(paceColor)
            }
            Text(subline)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if runner.hasRoutine {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(runner.segments) { seg in
                                row(seg).id(seg.id)
                            }
                        }
                    }
                    .onChange(of: runner.index) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
                    .onChange(of: expanded) { _, e in if e { proxy.scrollTo(runner.index, anchor: .center) } }
                }
                .frame(maxHeight: .infinity)
            } else {
                Text("Open a .md file: `5m intro, 10m demo, ? questions` — one line or one segment per line.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .center)
            }

            controls
        }
    }

    private var paceSentence: String {
        switch runner.state {
        case .idle: return runner.hasRoutine ? "ready" : ""
        case .finished:
            let d = runner.drift
            if abs(d) < runner.paceTolerance { return "finished on time" }
            return d > 0 ? "finished \(Duration.format(d)) over" : "finished \(Duration.format(-d)) under"
        case .running, .paused:
            switch runner.pace {
            case .onTrack: return "on track"
            case .behind(let by): return "speed up · behind \(Duration.format(by))"
            case .ahead(let by): return "slow down · ahead \(Duration.format(by))"
            }
        }
    }

    private var paceColor: Color {
        guard runner.hasStarted else { return .secondary }
        if runner.state == .finished {
            return abs(runner.drift) < runner.paceTolerance ? .green : (runner.drift > 0 ? .red : .green)
        }
        switch runner.pace {
        case .onTrack: return .green
        case .behind: return .red
        case .ahead: return .green
        }
    }

    private var subline: String {
        let clock = Date.FormatStyle(date: .omitted, time: .shortened)
        switch runner.state {
        case .idle:
            guard runner.hasRoutine else { return "nothing loaded" }
            let sw = runner.segments.filter(\.isStopwatch).count
            var s = "\(runner.segments.count) segments · \(Duration.format(runner.plannedTotal)) planned"
            if sw > 0 { s += " · \(sw) open-ended" }
            return s
        case .finished:
            return "took \(Duration.format(runner.totalElapsed)) of \(Duration.format(runner.plannedTotal))"
        case .running, .paused:
            var s = "ends \(runner.projectedEnd.formatted(clock))"
            if let p = runner.plannedEnd { s += " · planned \(p.formatted(clock))" }
            s += " · \(Duration.format(runner.totalRemaining)) left"
            return s
        }
    }

    private func row(_ seg: Segment) -> some View {
        let i = seg.id
        let isCurrent = i == runner.index && runner.state != .finished
        let done = runner.isDone(i)
        let actual = runner.actualFor(i)
        let plannedText = seg.planned.map { Duration.format($0) } ?? "∞"
        let timeText: String = (done || isCurrent) ? "\(Duration.format(actual)) / \(plannedText)" : plannedText
        let timeColor: Color = {
            guard done || isCurrent, let p = seg.planned else { return done || isCurrent ? .white : .secondary }
            if actual > p { return .red }
            return done ? .green : .white
        }()

        return HStack(spacing: 8) {
            Text("\(i + 1)")
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(seg.name)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(done && !isCurrent ? .secondary : .primary)
            Spacer()
            Text(timeText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timeColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(isCurrent ? 0.10 : 0))
                if isCurrent, let p = runner.progress {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 6)
                            .fill((runner.currentRemaining ?? 0) < 0 ? Color.red.opacity(0.35) : Color.white.opacity(0.16))
                            .frame(width: geo.size.width * p)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { runner.jump(to: i) }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            control("backward.end.fill", enabled: runner.hasStarted) { runner.previous() }
            control(runner.state == .running ? "pause.fill" : "play.fill", enabled: runner.hasRoutine && runner.state != .finished) {
                actions.playPause()
            }
            control("forward.end.fill", enabled: runner.state == .running || runner.state == .paused) { runner.next() }
            control("arrow.counterclockwise", enabled: runner.hasStarted) { runner.reset() }
            Spacer()
            if state.pendingReload {
                Button { actions.reload() } label: {
                    Label("file changed · reload", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            control("folder", enabled: true) { actions.open() }
            control("power", enabled: true) { actions.quit() }
        }
        .padding(.top, 2)
    }

    private func control(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
