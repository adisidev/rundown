import Foundation
import Combine

/// Publishes the current time a few times a second so views re-read the Runner's Date-based values.
final class Ticker: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?

    init(interval: TimeInterval = 0.25) {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.now = Date() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }
}
