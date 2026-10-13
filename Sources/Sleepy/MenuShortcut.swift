import AppKit
import Carbon.HIToolbox

/// The global shortcut that opens and closes the Sleepy menu.
enum MenuShortcut: String, CaseIterable {
    case commandOptionZ
    case controlOptionZ
    case optionSpace
    case off

    static let defaultsKey = "menuShortcut"

    static var current: MenuShortcut {
        get {
            guard
                let raw = UserDefaults.standard.string(forKey: defaultsKey),
                let shortcut = MenuShortcut(rawValue: raw)
            else {
                return .commandOptionZ
            }
            return shortcut
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var displayName: String {
        switch self {
        case .commandOptionZ: "⌘⌥Z"
        case .controlOptionZ: "⌃⌥Z"
        case .optionSpace: "⌥Space"
        case .off: "Off"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .commandOptionZ, .controlOptionZ: UInt32(kVK_ANSI_Z)
        case .optionSpace: UInt32(kVK_Space)
        case .off: nil
        }
    }

    /// The same combination expressed for a menu item, which is how the menu
    /// closes itself while it is the one holding the keyboard.
    var keyEquivalent: String {
        switch self {
        case .commandOptionZ, .controlOptionZ: "z"
        case .optionSpace: " "
        case .off: ""
        }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        switch self {
        case .commandOptionZ: [.command, .option]
        case .controlOptionZ: [.control, .option]
        case .optionSpace: [.option]
        case .off: []
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .commandOptionZ: UInt32(cmdKey | optionKey)
        case .controlOptionZ: UInt32(controlKey | optionKey)
        case .optionSpace: UInt32(optionKey)
        case .off: 0
        }
    }
}

/// A system-wide hot key, registered through the one API that needs no
/// permission prompt to listen for one.
@MainActor
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?

    /// Returns false when the combination is already spoken for.
    func register(_ shortcut: MenuShortcut, onPress: @escaping () -> Void) -> Bool {
        unregister()

        guard let keyCode = shortcut.keyCode else { return false }
        self.onPress = onPress

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().fire()
                }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        let identifier = EventHotKeyID(signature: OSType(0x534C5059), id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        if status != noErr {
            unregister()
            return false
        }

        return true
    }

    func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        onPress = nil
    }

    /// Called straight from Carbon's own event handling, so whatever the
    /// handler does must be quick. Opening a menu here would enter a modal
    /// tracking loop mid-dispatch and leave the keystroke to be delivered
    /// again when tracking unwinds, so callers defer the real work.
    private func fire() {
        onPress?()
    }
}
