import SwiftUI
import RundownCore

struct NotchView: View {
    @ObservedObject var runner: Runner
    @ObservedObject var ticker: Ticker
    @ObservedObject var state: PanelState
    let actions: PanelActions

    private var g: NotchGeometry { state.geometry }
    /// Pointer position (screen coordinates) and body size when a resize drag began.
    @State private var resizeStart: (mouse: CGPoint, size: CGSize)?
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
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
            .clipped()
            if expanded {
                resizeGrip
                    .frame(width: width, height: height, alignment: .bottomTrailing)
                    .transition(.opacity)
            }
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
            Button("Scratch Routine") { actions.scratch() }
            Button("Edit in Editor") { actions.edit() }.disabled(state.fileName == nil)
            Divider()
            Button(runner.state == .running ? "Pause" : "Start / Resume") { actions.playPause() }
                .disabled(!runner.hasRoutine || runner.state == .finished)
            Button("Reset") { runner.reset() }.disabled(!runner.hasStarted)
            Button("Tick Next Item") { runner.checkNext() }.disabled(runner.openItems(in: runner.index).isEmpty)
            Toggle("Count Up (ignore durations)", isOn: Binding(get: { runner.countUp }, set: { actions.setCountUp($0) }))
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
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
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
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            paceChip
            checklistChip
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
            return runner.planned(runner.index).map { Duration.format($0) } ?? "⏱"
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
        if runner.isUntimed, runner.hasRoutine {
            return runner.state == .idle ? "⏱" : Duration.format(runner.totalElapsed)
        }
        switch runner.state {
        case .idle: return runner.hasRoutine ? Duration.format(runner.plannedTotal) : "open a routine"
        case .finished: return Duration.format(runner.drift, signed: true)
        case .running, .paused: return Duration.format(runner.totalRemaining)
        }
    }

    /// Ticked / total for the current segment's checklist; after the run, how many were missed overall.
    @ViewBuilder private var checklistChip: some View {
        if runner.state == .finished, runner.hasChecklist {
            let missed = runner.missedCount
            Label(missed == 0 ? "all" : "\(missed)", systemImage: missed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(missed == 0 ? .green : .orange)
        } else if let seg = runner.current, !seg.items.isEmpty {
            let done = seg.items.count - runner.openItems(in: runner.index).count
            Label("\(done)/\(seg.items.count)", systemImage: "checklist")
                .labelStyle(.titleOnly)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(done == seg.items.count ? Color.green : Color.white.opacity(0.8))
        }
    }

    /// The right wing is too narrow for both the pace amount and the checklist count; with a checklist showing,
    /// the pace chip drops its number (the expanded view still has it).
    private var compactChecklist: Bool { !(runner.current?.items.isEmpty ?? true) && runner.state != .finished }

    @ViewBuilder private var paceChip: some View {
        if runner.isUntimed {
            EmptyView()
        } else if runner.hasStarted, runner.state != .finished {
            switch runner.pace {
            case .onTrack:
                Circle().fill(.green).frame(width: 7, height: 7)
            case .behind(let by):
                Label(Duration.format(by), systemImage: "arrowtriangle.up.fill")
                    .labelStyle(compactChecklist ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.red)
            case .ahead(let by):
                Label(Duration.format(by), systemImage: "arrowtriangle.down.fill")
                    .labelStyle(compactChecklist ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
        } else if runner.state == .idle, runner.hasRoutine, runner.current?.items.isEmpty ?? true {
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
            Text(state.loadError.map { "⚠︎ " + $0 } ?? subline)
                .font(.system(size: 11))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(state.loadError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))

            if runner.hasRoutine {
                if state.snapshot {
                    VStack(spacing: 2) { ForEach(runner.segments) { row($0) } }
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
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
                }
            } else {
                Text("Open a .md file, or start a scratch routine (✎) and edit it in your markdown editor: `5m intro, 10m demo, ? questions` — one line or one segment per line.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .center)
            }

            controls
        }
    }

    private var paceSentence: String {
        if runner.isUntimed || runner.state == .finished, runner.hasChecklist, runner.hasStarted {
            let missed = runner.missedCount
            if runner.state == .finished { return missed == 0 ? "everything covered" : "\(missed) missed" }
            let open = runner.itemCount - runner.checkedCount
            if missed > 0 { return "\(missed) missed · \(open) open" }
            return open == 0 ? "everything covered" : "\(open) open"
        }
        if runner.isUntimed, runner.hasStarted {
            return runner.state == .finished ? "finished" : "counting up"
        }
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
        if runner.isUntimed || runner.state == .finished, runner.hasChecklist {
            return runner.missedCount > 0 ? .orange : (runner.checkedCount == runner.itemCount ? .green : .secondary)
        }
        if runner.isUntimed { return .secondary }
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
            var s = "\(runner.segments.count) segments"
            if runner.isUntimed {
                s += " · counts up"
            } else {
                s += " · \(Duration.format(runner.plannedTotal)) planned"
                let sw = runner.segments.indices.filter { runner.planned($0) == nil }.count
                if sw > 0 { s += " · \(sw) open-ended" }
            }
            if runner.hasChecklist { s += " · \(runner.itemCount) to cover" }
            return s
        case .finished:
            var s = "took \(Duration.format(runner.totalElapsed))"
            if !runner.isUntimed { s += " of \(Duration.format(runner.plannedTotal))" }
            if runner.hasChecklist { s += " · \(runner.checkedCount)/\(runner.itemCount) covered" }
            return s
        case .running, .paused:
            if runner.isUntimed {
                var s = "started \((runner.startedAt ?? runner.now()).formatted(clock)) · \(Duration.format(runner.totalElapsed)) in"
                if runner.hasChecklist { s += " · \(runner.checkedCount)/\(runner.itemCount) covered" }
                return s
            }
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
        let planned = runner.planned(i)
        let plannedText = planned.map { Duration.format($0) } ?? "∞"
        let timeText: String = {
            guard done || isCurrent else { return planned == nil && runner.isUntimed ? "" : plannedText }
            return planned == nil ? Duration.format(actual) : "\(Duration.format(actual)) / \(plannedText)"
        }()
        let open = runner.openItems(in: i)
        let showItems = !seg.items.isEmpty && (isCurrent || (done && !open.isEmpty))
        let timeColor: Color = {
            guard done || isCurrent, let p = planned else { return done || isCurrent ? .white : .secondary }
            if actual > p { return .red }
            return done ? .green : .white
        }()

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
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
            if !seg.items.isEmpty, !showItems {
                Text("\(seg.items.count - open.count)/\(seg.items.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(open.isEmpty ? Color.green : Color.secondary)
            }
            Text(timeText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timeColor)
            }
            .padding(.vertical, 1)
            .background {
                if isCurrent, let p = runner.progress {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill((runner.currentRemaining ?? 0) < 0 ? Color.red.opacity(0.35) : Color.white.opacity(0.16))
                            .frame(width: geo.size.width * p)
                    }
                    .padding(.horizontal, -4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { runner.jump(to: i) }
            if showItems {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(isCurrent ? seg.items : open) { item in itemRow(item, missed: done && !isCurrent) }
                }
                .padding(.leading, 24)
                .padding(.top, 3)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(isCurrent ? 0.10 : 0)))
    }

    private func itemRow(_ item: ChecklistItem, missed: Bool) -> some View {
        let on = runner.isChecked(item)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.system(size: 11))
                .foregroundStyle(on ? Color.green : (missed ? Color.orange : Color.secondary))
            Text(item.text)
                .font(.system(size: 11))
                .lineLimit(2)
                .strikethrough(on, color: .secondary)
                .foregroundStyle(on ? AnyShapeStyle(.secondary) : AnyShapeStyle(missed ? Color.orange : Color.primary))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { runner.toggle(item) }
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
            if runner.state == .finished, runner.missedCount > 0 {
                Button { actions.copyMissed() } label: {
                    Label("copy missed", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            if state.pendingReload {
                Button { actions.reload() } label: {
                    Label("file changed · reload", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            control(state.pinned ? "pin.fill" : "pin", enabled: true) { actions.togglePin() }
                .help(state.pinned ? "Unpin: close when the pointer leaves" : "Pin: keep the panel open")
            control("folder", enabled: true) { actions.open() }
            control("square.and.pencil", enabled: true) { actions.scratch() }
            control("pencil", enabled: state.fileName != nil) { actions.edit() }
            control("power", enabled: true) { actions.quit() }
        }
        .padding(.top, 2)
    }

    /// Bottom-right corner grip: drag to resize (width grows on both sides, since the panel stays centred),
    /// double-click to go back to the default size. Uses the screen pointer position, because the window itself
    /// moves and resizes under the drag.
    private var resizeGrip: some View {
        Path { p in
            for i in 0..<3 {
                let o = CGFloat(i) * 4
                p.move(to: CGPoint(x: 11, y: o + 1))
                p.addLine(to: CGPoint(x: o + 1, y: 11))
            }
        }
        .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        .frame(width: 12, height: 12)
        .padding(5)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    let m = NSEvent.mouseLocation
                    if resizeStart == nil {
                        resizeStart = (m, CGSize(width: g.bodyWidth, height: g.bodyHeight))
                        state.resizing = true
                    }
                    guard let s = resizeStart else { return }
                    actions.resize(CGSize(width: s.size.width + 2 * (m.x - s.mouse.x),
                                          height: s.size.height - (m.y - s.mouse.y)))
                }
                .onEnded { _ in
                    resizeStart = nil
                    state.resizing = false
                    actions.resizeEnded()
                }
        )
        .onTapGesture(count: 2) { actions.resizeReset() }
        .help("Drag to resize · double-click to reset")
        .padding(.trailing, 3)
        .padding(.bottom, 3)
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

private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(Label($0).labelStyle(style)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
