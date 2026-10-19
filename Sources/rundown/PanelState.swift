import Foundation
import Combine
import CoreGraphics

/// Geometry of the notch on the display the panel lives on, plus the panel's compact/expanded sizes (in points).
struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var wing: CGFloat = 124
    /// Taller expanded view for routines with checklists.
    var tall = false

    var compactWidth: CGFloat { notchWidth + 2 * wing }
    /// Notch height on notched screens; on others `notchHeight` holds the menu bar's height, so the bar sits in the menu bar.
    var compactHeight: CGFloat { notchHeight > 0 ? notchHeight : 24 }
    var expandedWidth: CGFloat { max(compactWidth, 440) }
    var expandedHeight: CGFloat { compactHeight + (tall ? 330 : 216) }

    static let pill = NotchGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0)
}

/// UI-only state shared between AppKit (hover tracking, geometry) and the SwiftUI view.
final class PanelState: ObservableObject {
    @Published var geometry = NotchGeometry.pill
    @Published var expanded = false
    @Published var pendingReload = false
    @Published var fileName: String?
    /// Parse error from the last watched reload, shown inline instead of an alert.
    @Published var loadError: String?
    /// Rendering for `--snapshot` (no scroll view, which offscreen rendering leaves blank).
    var snapshot = false
}

/// Things the view can ask the app to do.
struct PanelActions {
    var primary: () -> Void = {}
    var playPause: () -> Void = {}
    var open: () -> Void = {}
    var reload: () -> Void = {}
    var quit: () -> Void = {}
    var scratch: () -> Void = {}
    var edit: () -> Void = {}
    var setCountUp: (Bool) -> Void = { _ in }
    var copyMissed: () -> Void = {}
}
