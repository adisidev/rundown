import Foundation

/// Watches one file for writes, including the rename-into-place saves most editors do.
final class FileWatcher {
    let url: URL
    private let handler: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(url: URL, handler: @escaping () -> Void) {
        self.url = url
        self.handler = handler
        start()
    }

    deinit { stop() }

    private func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File missing (mid-save?); try again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start() }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            if flags.contains(.rename) || flags.contains(.delete) {
                self.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.start()
                    self?.fire()
                }
            } else {
                self.fire()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func stop() {
        source?.cancel()
        source = nil
    }

    private func fire() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.handler() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }
}
