import AppKit
import SwiftUI
import RundownCore

/// A borderless, non-activating panel pinned to the top of the display that has the notch (or the main display).
///
/// Sizing approach: the panel's frame is *always* the expanded size. The SwiftUI view draws the black compact or
/// expanded shape inside it and leaves the rest transparent; macOS passes clicks through fully transparent pixels of a
/// non-opaque window, so the invisible margin never steals input from the menu bar or apps below. Hover is tracked in
/// AppKit (`HoverView`) with `.activeAlways` so it works while another app is frontmost, and is checked against the
/// current shape rect so nothing expands when the cursor is merely inside the panel's transparent bounds.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HoverView: NSView {
    var shapeRect: () -> CGRect = { .zero }
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self)
        addTrackingArea(a)
        area = a
    }

    private func check(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onHover(shapeRect().contains(p))
    }

    override func mouseEntered(with event: NSEvent) { check(event) }
    override func mouseMoved(with event: NSEvent) { check(event) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

final class HostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchPanelController {
    let panel: NotchPanel
    let state: PanelState
    private let hover = HoverView()
    private var collapseTimer: Timer?
    private var screenObserver: Any?

    init(runner: Runner, ticker: Ticker, state: PanelState, actions: PanelActions) {
        self.state = state
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none

        let content = NotchView(runner: runner, ticker: ticker, state: state, actions: actions)
        let hosting = HostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        hover.addSubview(hosting)
        hover.shapeRect = { [weak self] in self?.shapeRect() ?? .zero }
        hover.onHover = { [weak self] inside in self?.setHover(inside) }
        panel.contentView = hover

        layout()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.layout() }
        panel.orderFrontRegardless()
    }

    var isVisible: Bool { panel.isVisible }

    func setTall(_ tall: Bool) {
        guard state.geometry.tall != tall else { return }
        state.geometry.tall = tall
        layout()
    }

    func toggleVisibility() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// Picks the screen with a notch (safe-area inset at the top), else the main screen, and pins the panel there.
    func layout() {
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? NSScreen.main ?? screens.first else { return }

        var g = NotchGeometry.pill
        g.tall = state.geometry.tall
        var centerX = screen.frame.midX
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            g = NotchGeometry(hasNotch: true,
                              notchWidth: right.minX - left.maxX,
                              notchHeight: screen.safeAreaInsets.top,
                              tall: g.tall)
            centerX = (left.maxX + right.minX) / 2
        }
        state.geometry = g
        let frame = CGRect(x: centerX - g.expandedWidth / 2,
                           y: screen.frame.maxY - g.expandedHeight,
                           width: g.expandedWidth, height: g.expandedHeight)
        panel.setFrame(frame, display: true)
        hover.frame = CGRect(origin: .zero, size: frame.size)
        hover.subviews.first?.frame = hover.bounds
        hover.updateTrackingAreas()
    }

    /// The black shape's rect in the content view's (bottom-left origin) coordinates.
    private func shapeRect() -> CGRect {
        let g = state.geometry
        let w = state.expanded ? g.expandedWidth : g.compactWidth
        let h = state.expanded ? g.expandedHeight : g.compactHeight
        return CGRect(x: (g.expandedWidth - w) / 2, y: g.expandedHeight - h, width: w, height: h)
    }

    private func setHover(_ inside: Bool) {
        if inside {
            collapseTimer?.invalidate()
            collapseTimer = nil
            if !state.expanded { state.expanded = true }
        } else if state.expanded, collapseTimer == nil {
            collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                self?.state.expanded = false
                self?.collapseTimer = nil
            }
        }
    }
}
