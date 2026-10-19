import AppKit
import SwiftUI
import Carbon
import Combine
import RundownCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    let runner = Runner()
    let ticker = Ticker()
    let panelState = PanelState()
    private var panel: NotchPanelController!
    private var statusItem: NSStatusItem!
    private var hotKeys: HotKeys!
    private var cancellables = Set<AnyCancellable>()

    private var currentURL: URL?
    private var watcher: FileWatcher?

    private let recentsKey = "recentFiles"
    private var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentsKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(8)), forKey: recentsKey) }
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        let actions = PanelActions(
            primary: { [weak self] in self?.primaryAction() },
            playPause: { [weak self] in self?.runner.togglePause() },
            open: { [weak self] in self?.openRoutine() },
            reload: { [weak self] in self?.reload(force: true) },
            quit: { NSApp.terminate(nil) },
            scratch: { [weak self] in self?.openScratch() },
            edit: { [weak self] in self?.editRoutine() },
            setCountUp: { [weak self] in self?.setCountUp($0) },
            copyMissed: { [weak self] in self?.copyMissed() }
        )
        panel = NotchPanelController(runner: runner, ticker: ticker, state: panelState, actions: actions)
        panel.pinnedScreen = UserDefaults.standard.string(forKey: pinnedScreenKey)
        setupStatusItem()
        setupHotKeys()

        ticker.$now.sink { [weak self] _ in self?.updateStatusTitle() }.store(in: &cancellables)
        runner.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in self?.rebuildMenu() }.store(in: &cancellables)
        runner.$state.removeDuplicates().dropFirst().sink { [weak self] state in
            if state == .finished { DispatchQueue.main.async { self?.writeRunLog() } }
        }.store(in: &cancellables)

        let args = CommandLine.arguments.dropFirst()
        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            MainActor.assumeIsolated { snapshot(file: args.first(where: { !$0.hasPrefix("-") && $0 != args[i + 1] }), to: args[i + 1]) }
            return
        }
        if args.contains("--scratch") {
            openScratch()
        } else if let path = args.first(where: { !$0.hasPrefix("-") }) {
            load(URL(fileURLWithPath: path))
        } else if let last = recents.first, FileManager.default.fileExists(atPath: last) {
            load(URL(fileURLWithPath: last))
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { load(url) }
    }

    /// `--snapshot <out.png> [file]`: renders the expanded panel mid-run (12 minutes in, on the second segment, a few
    /// items ticked) to a PNG and quits. For README screenshots and checking layout without hovering.
    @MainActor private func snapshot(file: String?, to out: String) {
        if let file { load(URL(fileURLWithPath: file)) }
        let t0 = Date()
        var offset: TimeInterval = 0
        runner.now = { t0.addingTimeInterval(offset) }
        runner.start()
        runner.checkNext()
        offset = 330; runner.next()
        runner.checkNext(); runner.checkNext()
        offset = 720
        panelState.geometry = NotchGeometry(hasNotch: true, notchWidth: 185, notchHeight: 32, tall: runner.hasChecklist)
        panelState.expanded = true
        panelState.snapshot = true
        panelState.fileName = file.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        let view = NotchView(runner: runner, ticker: ticker, state: panelState, actions: PanelActions())
        let renderer = ImageRenderer(content: view.background(Color(white: 0.85)))
        renderer.scale = 2
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
        }
        exit(0)
    }

    // MARK: Status item + menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "rundown")
            button.imagePosition = .imageLeading
        }
        rebuildMenu()
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        let text: String
        switch runner.state {
        case .idle: text = ""
        case _ where runner.isUntimed: text = Duration.format(runner.totalElapsed)
        case .finished: text = Duration.format(runner.drift, signed: true)
        case .running, .paused: text = Duration.format(runner.totalRemaining)
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [.font: font])
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Routine…", action: #selector(openRoutine), keyEquivalent: "o")
        menu.addItem(open)
        let scratch = NSMenuItem(title: "Scratch Routine", action: #selector(openScratch), keyEquivalent: "n")
        scratch.toolTip = "A personal scratch file you can edit on the go; opens in your default markdown editor and reloads on save."
        menu.addItem(scratch)

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        for path in recents {
            let item = NSMenuItem(title: (path as NSString).abbreviatingWithTildeInPath, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = path
            recentMenu.addItem(item)
        }
        if recents.isEmpty {
            recentMenu.addItem(NSMenuItem(title: "No recent files", action: nil, keyEquivalent: ""))
        } else {
            recentMenu.addItem(.separator())
            recentMenu.addItem(NSMenuItem(title: "Clear Menu", action: #selector(clearRecents), keyEquivalent: ""))
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadFromMenu), keyEquivalent: "r")
        reloadItem.isEnabled = currentURL != nil
        menu.addItem(reloadItem)
        let edit = NSMenuItem(title: "Edit Routine…", action: #selector(editRoutine), keyEquivalent: "e")
        edit.isEnabled = currentURL != nil
        menu.addItem(edit)
        if let url = currentURL {
            let info = NSMenuItem(title: url.lastPathComponent, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(.separator())

        let ctrlOpt: NSEvent.ModifierFlags = [.control, .option]
        let playTitle: String = {
            switch runner.state {
            case .idle: return "Start"
            case .running: return "Pause"
            case .paused: return "Resume"
            case .finished: return "Finished"
            }
        }()
        let play = NSMenuItem(title: playTitle, action: #selector(togglePause), keyEquivalent: " ")
        play.keyEquivalentModifierMask = ctrlOpt
        play.isEnabled = runner.hasRoutine && runner.state != .finished
        menu.addItem(play)

        let next = NSMenuItem(title: "Next Segment", action: #selector(nextSegment), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        next.keyEquivalentModifierMask = ctrlOpt
        next.isEnabled = runner.state == .running || runner.state == .paused
        menu.addItem(next)

        let prev = NSMenuItem(title: "Previous Segment", action: #selector(previousSegment), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        prev.keyEquivalentModifierMask = ctrlOpt
        prev.isEnabled = runner.hasStarted
        menu.addItem(prev)

        let reset = NSMenuItem(title: "Reset", action: #selector(resetRun), keyEquivalent: "r")
        reset.keyEquivalentModifierMask = ctrlOpt
        reset.isEnabled = runner.hasStarted
        menu.addItem(reset)

        let tick = NSMenuItem(title: "Tick Next Item", action: #selector(tickNext), keyEquivalent: "c")
        tick.keyEquivalentModifierMask = ctrlOpt
        tick.isEnabled = !runner.openItems(in: runner.index).isEmpty
        menu.addItem(tick)

        let countUp = NSMenuItem(title: "Count Up (ignore durations)", action: #selector(toggleCountUp), keyEquivalent: "u")
        countUp.keyEquivalentModifierMask = ctrlOpt
        countUp.state = runner.countUp ? .on : .off
        countUp.toolTip = "Run the same file as a stopwatch: everything counts up, no countdowns or pace. Remembered per file."
        countUp.isEnabled = runner.hasRoutine
        menu.addItem(countUp)
        menu.addItem(.separator())

        let copy = NSMenuItem(title: "Copy Missed Items", action: #selector(copyMissed), keyEquivalent: "")
        copy.isEnabled = runner.hasStarted && runner.missedCount > 0
        menu.addItem(copy)
        menu.addItem(NSMenuItem(title: "Show Past Runs", action: #selector(showRuns), keyEquivalent: ""))
        menu.addItem(.separator())

        let show = NSMenuItem(title: panel.isVisible ? "Hide Panel" : "Show Panel", action: #selector(togglePanel), keyEquivalent: "n")
        show.keyEquivalentModifierMask = ctrlOpt
        menu.addItem(show)

        let showOn = NSMenuItem(title: "Show On", action: nil, keyEquivalent: "")
        let screensMenu = NSMenu()
        let follow = NSMenuItem(title: "Display You're Working On", action: #selector(pinScreen(_:)), keyEquivalent: "")
        follow.state = panel.pinnedScreen == nil ? .on : .off
        screensMenu.addItem(follow)
        screensMenu.addItem(.separator())
        for screen in NSScreen.screens {
            let item = NSMenuItem(title: screen.localizedName, action: #selector(pinScreen(_:)), keyEquivalent: "")
            item.representedObject = screen.localizedName
            item.state = panel.pinnedScreen == screen.localizedName ? .on : .off
            screensMenu.addItem(item)
        }
        showOn.submenu = screensMenu
        menu.addItem(showOn)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit rundown", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = ctrlOpt
        menu.addItem(quit)

        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: Hotkeys

    private func setupHotKeys() {
        hotKeys = HotKeys()
        let mods = controlKey | optionKey
        hotKeys.register(keyCode: KeyCode.space, modifiers: mods) { [weak self] in self?.runner.togglePause() }
        hotKeys.register(keyCode: KeyCode.rightArrow, modifiers: mods) { [weak self] in self?.runner.next() }
        hotKeys.register(keyCode: KeyCode.leftArrow, modifiers: mods) { [weak self] in self?.runner.previous() }
        hotKeys.register(keyCode: KeyCode.r, modifiers: mods) { [weak self] in self?.runner.reset() }
        hotKeys.register(keyCode: KeyCode.n, modifiers: mods) { [weak self] in self?.panel.toggleVisibility() }
        hotKeys.register(keyCode: KeyCode.q, modifiers: mods) { NSApp.terminate(nil) }
        hotKeys.register(keyCode: KeyCode.c, modifiers: mods) { [weak self] in self?.runner.checkNext() }
        hotKeys.register(keyCode: KeyCode.u, modifiers: mods) { [weak self] in self?.toggleCountUp() }
    }

    // MARK: Actions

    private func primaryAction() {
        switch runner.state {
        case .idle: runner.hasRoutine ? runner.start() : openRoutine()
        case .running: runner.next()
        case .paused: runner.resume()
        case .finished: runner.reset()
        }
    }

    @objc private func togglePause() { runner.togglePause() }
    @objc private func nextSegment() { runner.next() }
    @objc private func previousSegment() { runner.previous() }
    @objc private func resetRun() { runner.reset() }
    @objc private func togglePanel() { panel.toggleVisibility(); rebuildMenu() }
    @objc private func reloadFromMenu() { reload(force: true) }
    @objc private func clearRecents() { recents = []; rebuildMenu() }
    @objc private func tickNext() { runner.checkNext() }

    private let pinnedScreenKey = "pinnedScreen"

    @objc private func pinScreen(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String
        panel.pinnedScreen = name
        UserDefaults.standard.set(name, forKey: pinnedScreenKey)
        rebuildMenu()
    }
    @objc private func toggleCountUp() { setCountUp(!runner.countUp) }

    // MARK: Count-up mode (remembered per file)

    private let countUpKey = "countUpFiles"

    private func setCountUp(_ on: Bool) {
        runner.countUp = on
        guard let path = currentURL?.path else { return }
        var files = Set(UserDefaults.standard.stringArray(forKey: countUpKey) ?? [])
        if on { files.insert(path) } else { files.remove(path) }
        UserDefaults.standard.set(Array(files), forKey: countUpKey)
        rebuildMenu()
    }

    // MARK: Checklist follow-ups

    @objc private func copyMissed() {
        guard let text = Report.missed(runner) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var runsURL: URL {
        let dir = scratchURL.deletingLastPathComponent().appendingPathComponent("runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @objc private func showRuns() { NSWorkspace.shared.open(runsURL) }

    /// Saves a markdown log of the finished run (times, ticked and missed items). Keyed by start time, so finishing
    /// again after stepping back overwrites the same file.
    private func writeRunLog() {
        guard let started = runner.startedAt else { return }
        let title = runner.routine?.title ?? panelState.fileName ?? "rundown"
        let stamp = started.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        let url = runsURL.appendingPathComponent("\(stamp) \(safe).md")
        try? Report.markdown(runner, title: title).write(to: url, atomically: true, encoding: .utf8)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        load(URL(fileURLWithPath: path))
    }

    @objc private func openRoutine() {
        let dialog = NSOpenPanel()
        dialog.title = "Open a routine"
        dialog.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText, .text]
        dialog.allowsOtherFileTypes = true
        dialog.canChooseDirectories = false
        if let url = currentURL { dialog.directoryURL = url.deletingLastPathComponent() }
        NSApp.activate(ignoringOtherApps: true)
        if dialog.runModal() == .OK, let url = dialog.url { load(url) }
    }

    @objc private func editRoutine() {
        guard let url = currentURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Scratch routine

    private static let scratchTemplate = """
    # Scratch routine

    <!-- One segment per line or comma-separated. Durations: 5m, 90s, 1h30m, 2:30. "?" = stopwatch (open-ended). "- [ ] thing" under a segment = something to cover in it. Edits reload while idle. -->

    5m intro
    10m main part
    - [ ] the one point that has to land
    ? questions

    """

    private var scratchURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("rundown", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scratch.md")
    }

    /// Loads the personal scratch file (creating it from a template on first use) and opens it in the default markdown editor.
    @objc private func openScratch() {
        let url = scratchURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Self.scratchTemplate.write(to: url, atomically: true, encoding: .utf8)
        }
        load(url)
        NSWorkspace.shared.open(url)
    }

    // MARK: Loading

    private func load(_ url: URL, quiet: Bool = false) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let routine = try Parser.parse(text)
            runner.load(routine)
            runner.countUp = (UserDefaults.standard.stringArray(forKey: countUpKey) ?? []).contains(url.path)
            panel.setTall(runner.hasChecklist)
            currentURL = url
            panelState.fileName = url.deletingPathExtension().lastPathComponent
            panelState.pendingReload = false
            panelState.loadError = nil
            recents = [url.path] + recents.filter { $0 != url.path }
            watcher = FileWatcher(url: url) { [weak self] in self?.fileChanged() }
            rebuildMenu()
        } catch {
            if quiet {
                panelState.loadError = error.localizedDescription
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't load \(url.lastPathComponent)"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func fileChanged() {
        if runner.state == .idle { reload(force: true) } else { panelState.pendingReload = true }
    }

    /// Re-reads the current file. With `force` it replaces a running routine (resetting the run).
    private func reload(force: Bool) {
        guard let url = currentURL else { return }
        if !force, runner.state != .idle { panelState.pendingReload = true; return }
        load(url, quiet: true)
    }
}
