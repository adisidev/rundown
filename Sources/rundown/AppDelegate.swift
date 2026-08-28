import AppKit
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
            reload: { [weak self] in self?.reload(force: true) }
        )
        panel = NotchPanelController(runner: runner, ticker: ticker, state: panelState, actions: actions)
        setupStatusItem()
        setupHotKeys()

        ticker.$now.sink { [weak self] _ in self?.updateStatusTitle() }.store(in: &cancellables)
        runner.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in self?.rebuildMenu() }.store(in: &cancellables)

        if let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            load(URL(fileURLWithPath: path))
        } else if let last = recents.first, FileManager.default.fileExists(atPath: last) {
            load(URL(fileURLWithPath: last))
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { load(url) }
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
        menu.addItem(.separator())

        let show = NSMenuItem(title: panel.isVisible ? "Hide Panel" : "Show Panel", action: #selector(togglePanel), keyEquivalent: "n")
        show.keyEquivalentModifierMask = ctrlOpt
        menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit rundown", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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

    // MARK: Loading

    private func load(_ url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let routine = try Parser.parse(text)
            runner.load(routine)
            currentURL = url
            panelState.fileName = url.deletingPathExtension().lastPathComponent
            panelState.pendingReload = false
            recents = [url.path] + recents.filter { $0 != url.path }
            watcher = FileWatcher(url: url) { [weak self] in self?.fileChanged() }
            rebuildMenu()
        } catch {
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
        load(url)
    }
}
