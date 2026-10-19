import Foundation
import Combine
import CoreGraphics

/// Geometry of the notch on the display the panel lives on, plus the panel's compact/expanded sizes (in points).
struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var wing: CGFloat = 124
    /// Size of the expanded panel below the compact row; the user can drag it bigger or smaller.
    var bodyWidth: CGFloat = NotchGeometry.defaultBody.width
    var bodyHeight: CGFloat = NotchGeometry.defaultBody.height

    var compactWidth: CGFloat { notchWidth + 2 * wing }
    /// Notch height on notched screens; on others `notchHeight` holds the menu bar's height, so the bar sits in the menu bar.
    var compactHeight: CGFloat { notchHeight > 0 ? notchHeight : 24 }
    var expandedWidth: CGFloat { max(compactWidth, bodyWidth) }
    var expandedHeight: CGFloat { compactHeight + bodyHeight }

    static let defaultBody = CGSize(width: 440, height: 216)
    static let minBody = CGSize(width: 360, height: 150)

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
    /// Keep the expanded panel open when the pointer leaves it.
    @Published var pinned = false
    /// A resize drag is in progress (the pointer may leave the panel without collapsing it).
    var resizing = false
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
    var togglePin: () -> Void = {}
    /// Proposed body size during a resize drag; the controller clamps it to the screen.
    var resize: (CGSize) -> Void = { _ in }
    var resizeEnded: () -> Void = {}
    var resizeReset: () -> Void = {}
}
