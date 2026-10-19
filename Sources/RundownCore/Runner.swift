import Foundation
import Combine

/// Runs a routine. All timekeeping is Date-based (wall clock at start/pause/next), never accumulated from ticks,
/// so the UI can refresh at any rate without drifting. Inject `now` for tests.
public final class Runner: ObservableObject {
    public enum State: Equatable { case idle, running, paused, finished }

    public enum Pace: Equatable {
        case onTrack
        case behind(TimeInterval)
        case ahead(TimeInterval)
    }

    @Published public private(set) var routine: Routine?
    @Published public private(set) var state: State = .idle
    @Published public private(set) var index = 0
    /// Committed time per segment (excludes the currently ticking interval).
    @Published public private(set) var actual: [TimeInterval] = []
    @Published public private(set) var currentStart: Date?
    @Published public private(set) var startedAt: Date?
    /// Ids of ticked checklist items. Every run starts with nothing ticked, so one file is a reusable playbook.
    @Published public private(set) var checked: Set<Int> = []
    /// Count everything up and ignore planned durations (no countdowns, no pace).
    @Published public var countUp = false

    public var now: () -> Date
    /// |drift| below this counts as on track.
    public var paceTolerance: TimeInterval = 20

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: Routine access

    public var segments: [Segment] { routine?.segments ?? [] }
    public var hasRoutine: Bool { !segments.isEmpty }
    public var current: Segment? { segments.indices.contains(index) ? segments[index] : nil }
    public var isLast: Bool { index == segments.count - 1 }
    public var hasStarted: Bool { state != .idle }

    // MARK: Actions

    public func load(_ routine: Routine) {
        self.routine = routine
        reset()
    }

    public func reset() {
        state = .idle
        index = 0
        actual = Array(repeating: 0, count: segments.count)
        currentStart = nil
        startedAt = nil
        checked = []
    }

    // MARK: Checklist

    public func isChecked(_ item: ChecklistItem) -> Bool { checked.contains(item.id) }

    public func toggle(_ item: ChecklistItem) {
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
    }

    /// Ticks the first unticked item of the current segment and returns it (nil if there is none).
    @discardableResult
    public func checkNext() -> ChecklistItem? {
        guard let item = current?.items.first(where: { !checked.contains($0.id) }) else { return nil }
        checked.insert(item.id)
        return item
    }

    public func openItems(in i: Int) -> [ChecklistItem] {
        guard segments.indices.contains(i) else { return [] }
        return segments[i].items.filter { !checked.contains($0.id) }
    }

    public var itemCount: Int { routine?.items.count ?? 0 }
    public var checkedCount: Int { checked.count }
    public var hasChecklist: Bool { itemCount > 0 }

    /// Unticked items in segments already left behind (or all of them once finished).
    public var missedCount: Int { segments.indices.filter(isDone).map { openItems(in: $0).count }.reduce(0, +) }

    public func start() {
        guard state == .idle, hasRoutine else { return }
        let t = now()
        startedAt = t
        currentStart = t
        state = .running
    }

    public func pause() {
        guard state == .running else { return }
        commit()
        currentStart = nil
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        currentStart = now()
        state = .running
    }

    public func togglePause() {
        switch state {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        case .finished: break
        }
    }

    /// Finishes the current segment and moves on; on the last segment, finishes the routine.
    public func next() {
        guard state == .running || state == .paused else { return }
        commit()
        if isLast {
            currentStart = nil
            state = .finished
        } else {
            index += 1
            currentStart = state == .running ? now() : nil
        }
    }

    /// Goes back one segment and keeps accumulating into it. From `finished`, reopens the last segment.
    public func previous() {
        switch state {
        case .idle:
            return
        case .finished:
            state = .running
            currentStart = now()
        case .running, .paused:
            guard index > 0 else { return }
            commit()
            index -= 1
            currentStart = state == .running ? now() : nil
        }
    }

    public func jump(to i: Int) {
        guard segments.indices.contains(i) else { return }
        switch state {
        case .idle:
            index = i
        case .finished:
            index = i
            state = .running
            currentStart = now()
        case .running, .paused:
            commit()
            index = i
            currentStart = state == .running ? now() : nil
        }
    }

    private func commit() {
        guard let s = currentStart else { return }
        let t = now()
        actual[index] += t.timeIntervalSince(s)
        currentStart = t
    }

    // MARK: Derived values

    /// Time spent in segment `i` so far, including the live interval if it is the current one.
    public func actualFor(_ i: Int) -> TimeInterval {
        guard actual.indices.contains(i) else { return 0 }
        var a = actual[i]
        if i == index, let s = currentStart { a += now().timeIntervalSince(s) }
        return a
    }

    /// Planned duration of segment `i` as this run treats it: nil for stopwatch segments and in count-up mode.
    public func planned(_ i: Int) -> TimeInterval? {
        guard !countUp, segments.indices.contains(i) else { return nil }
        return segments[i].planned
    }

    /// No countdowns at all: count-up mode, or a routine without a single duration.
    public var isUntimed: Bool { countUp || routine?.plannedTotal ?? 0 == 0 }

    public var currentElapsed: TimeInterval { current == nil ? 0 : actualFor(index) }

    /// Planned minus elapsed for the current segment; negative when over. Nil for stopwatch segments.
    public var currentRemaining: TimeInterval? {
        guard let p = planned(index) else { return nil }
        return p - currentElapsed
    }

    public func isDone(_ i: Int) -> Bool {
        state == .finished || i < index
    }

    /// Seconds behind (positive) or ahead (negative) of the plan.
    /// Completed timed segments contribute `actual - planned`; the current timed segment contributes only its overtime.
    /// Stopwatch segments never contribute.
    public var drift: TimeInterval {
        var d: TimeInterval = 0
        for i in segments.indices where isDone(i) {
            if let p = planned(i) { d += actualFor(i) - p }
        }
        if state == .running || state == .paused, let p = planned(index) {
            d += max(0, currentElapsed - p)
        }
        return d
    }

    public var plannedTotal: TimeInterval { countUp ? 0 : routine?.plannedTotal ?? 0 }

    /// Planned time still to go: what's left of the current segment plus all future planned segments.
    public var totalRemaining: TimeInterval {
        switch state {
        case .idle: return plannedTotal
        case .finished: return 0
        case .running, .paused:
            let future = index + 1 < segments.count
                ? ((index + 1)..<segments.count).compactMap(planned).reduce(0, +)
                : 0
            return max(0, currentRemaining ?? 0) + future
        }
    }

    public var totalElapsed: TimeInterval { segments.indices.map(actualFor).reduce(0, +) }

    public var projectedEnd: Date { now().addingTimeInterval(totalRemaining) }

    public var plannedEnd: Date? { startedAt?.addingTimeInterval(plannedTotal) }

    public var pace: Pace {
        let d = drift
        if abs(d) < paceTolerance { return .onTrack }
        return d > 0 ? .behind(d) : .ahead(-d)
    }

    /// 0…1 through the current timed segment; nil for stopwatch segments.
    public var progress: Double? {
        guard let p = planned(index), p > 0 else { return nil }
        return min(1, max(0, currentElapsed / p))
    }
}
