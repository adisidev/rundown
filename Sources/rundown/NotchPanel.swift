import AppKit
import os
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
    static let log = Logger(subsystem: "dev.adisi.rundown", category: "panel")
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
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Let the newly active app's window come forward before reading the window list.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.followActiveScreen() }
            }
        }
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

    /// Name of the display to stay on; nil follows the display you're working on.
    var pinnedScreen: String? {
        didSet { layout() }
    }
    private var lastScreen: String?

    /// The display holding the frontmost app's frontmost window (window bounds need no permission), else the
    /// display with the pointer.
    private func activeScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let name = pinnedScreen, let s = screens.first(where: { $0.localizedName == name }) { return s }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let win = list.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let dict = win[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict)
        else {
            // Frontmost app has no window (e.g. Finder with none open): use the display the pointer is on.
            let mouse = NSEvent.mouseLocation
            return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? screens.first
        }
        // CG window bounds have a top-left origin on the primary display; flip to AppKit's bottom-left.
        let primaryHeight = screens.first?.frame.height ?? 0
        let center = CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
        return screens.first { $0.frame.contains(center) } ?? screens.first
    }

    /// Re-pins the panel if the active display changed (cheap enough to call on every app switch).
    func followActiveScreen() {
        guard pinnedScreen == nil, let s = activeScreen(), s.localizedName != lastScreen else { return }
        layout()
    }

    /// Pins the panel to the top of the active display: hugging the notch if it has one, else inside its menu bar.
    func layout() {
        guard let screen = activeScreen() else { return }
        lastScreen = screen.localizedName
        Self.log.notice("panel on \(screen.localizedName, privacy: .public) \(NSStringFromRect(screen.frame), privacy: .public) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-", privacy: .public)")

        var g = NotchGeometry.pill
        g.tall = state.geometry.tall
        // Menu bar height; zero when it auto-hides (compactHeight then falls back to 24).
        g.notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
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
