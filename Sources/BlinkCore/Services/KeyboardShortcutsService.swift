import AppKit
import Carbon.HIToolbox

public enum GlobalShortcut: String, CaseIterable, Sendable {
    case toggle
    case skip
    case reset
    case addFive
    case showFloating

    public var defaultKeyCode: UInt32 {
        switch self {
        case .toggle:        return UInt32(kVK_Space)
        case .skip:         return UInt32(kVK_ANSI_F)
        case .reset:        return UInt32(kVK_ANSI_R)
        case .addFive:      return UInt32(kVK_ANSI_Equal)
        case .showFloating: return UInt32(kVK_ANSI_L)
        }
    }

    public var defaultModifiers: UInt32 {
        UInt32(controlKey | optionKey)
    }

    public var label: String {
        switch self {
        case .toggle:        return "Start / Pauza"
        case .skip:         return "O'tkazib yubor"
        case .reset:        return "Reset"
        case .addFive:      return "+5 daqiqa"
        case .showFloating: return "Suzuvchi taymerni ko'rsat"
        }
    }
}

@MainActor
public final class KeyboardShortcutsService {
    public static let shared = KeyboardShortcutsService()

    public typealias Action = () -> Void

    private struct Entry {
        let shortcut: GlobalShortcut
        let ref: EventHotKeyRef
        let actionID: UInt32
    }

    private var entries: [Entry] = []
    private var actionsByID: [UInt32: Action] = [:]
    private var nextID: UInt32 = 1
    private var enabled = false
    private var eventHandler: EventHandlerRef?

    public init() {}

    public func update(_ actions: [GlobalShortcut: Action], enabled: Bool) {
        unregister()
        self.enabled = enabled
        guard enabled else { return }
        register(actions)
    }

    public func unregister() {
        for entry in entries { UnregisterEventHotKey(entry.ref) }
        entries.removeAll()
        actionsByID.removeAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        enabled = false
    }

    deinit {
        for entry in entries { UnregisterEventHotKey(entry.ref) }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Registration

    private func register(_ actions: [GlobalShortcut: Action]) {
        ensureEventHandlerInstalled()

        for shortcut in GlobalShortcut.allCases {
            guard let action = actions[shortcut] else { continue }
            let actionID = nextID
            nextID &+= 1
            actionsByID[actionID] = action

            let id = EventHotKeyID(signature: fourCharCode("blnk"),
                                   id: actionID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.defaultKeyCode,
                                             shortcut.defaultModifiers,
                                             id,
                                             GetApplicationEventTarget(),
                                             0,
                                             &ref)
            guard status == noErr, let hotKeyRef = ref else {
                actionsByID[actionID] = nil
                continue
            }
            entries.append(Entry(shortcut: shortcut, ref: hotKeyRef, actionID: actionID))
        }
    }

    private func ensureEventHandlerInstalled() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                          hotKeyCallback,
                                          1,
                                          &spec,
                                          context,
                                          &ref)
        if status == noErr {
            eventHandler = ref
        }
    }

    private func fourCharCode(_ s: String) -> OSType {
        var result: UInt32 = 0
        for char in s.unicodeScalars.prefix(4) {
            result = (result << 8) | char.value
        }
        return OSType(result)
    }

    fileprivate func dispatch(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        action()
    }
}

private let hotKeyCallback: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, event, userData in
    guard let event = event, let userData = userData else { return noErr }
    var id = EventHotKeyID()
    let size = MemoryLayout<EventHotKeyID>.size
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   size,
                                   nil,
                                   &id)
    guard status == noErr else { return noErr }

    let service = Unmanaged<KeyboardShortcutsService>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        service.dispatch(id: id.id)
    }
    return noErr
}