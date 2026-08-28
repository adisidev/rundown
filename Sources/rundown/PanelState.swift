import Foundation
import Combine
import CoreGraphics

/// Geometry of the notch on the display the panel lives on, plus the panel's compact/expanded sizes (in points).
struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var wing: CGFloat = 175

    var compactWidth: CGFloat { notchWidth + 2 * wing }
    var compactHeight: CGFloat { hasNotch ? notchHeight : 34 }
    var expandedWidth: CGFloat { max(compactWidth, 500) }
    var expandedHeight: CGFloat { compactHeight + 216 }

    static let pill = NotchGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0)
}

/// UI-only state shared between AppKit (hover tracking, geometry) and the SwiftUI view.
final class PanelState: ObservableObject {
    @Published var geometry = NotchGeometry.pill
    @Published var expanded = false
    @Published var pendingReload = false
    @Published var fileName: String?
}

/// Things the view can ask the app to do.
struct PanelActions {
    var primary: () -> Void = {}
    var playPause: () -> Void = {}
    var open: () -> Void = {}
    var reload: () -> Void = {}
}
