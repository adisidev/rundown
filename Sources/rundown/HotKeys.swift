import Carbon
import Foundation

/// Global hotkeys via Carbon's RegisterEventHotKey — works without the Accessibility permission.
final class HotKeys {
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let signature: OSType = "RNDN".utf8.reduce(0) { ($0 << 8) | OSType($1) }

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.actions[id.id]?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// `modifiers` are Carbon flags (`controlKey`, `optionKey`, `cmdKey`, `shiftKey`).
    @discardableResult
    func register(keyCode: UInt32, modifiers: Int, action: @escaping () -> Void) -> Bool {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, UInt32(modifiers), EventHotKeyID(signature: signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        actions[id] = action
        return true
    }
}

enum KeyCode {
    static let space: UInt32 = 49
    static let leftArrow: UInt32 = 123
    static let rightArrow: UInt32 = 124
    static let r: UInt32 = 15
    static let n: UInt32 = 45
    static let q: UInt32 = 12
    static let c: UInt32 = 8
    static let u: UInt32 = 32
}
