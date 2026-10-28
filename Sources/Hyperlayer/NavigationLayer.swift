import CoreGraphics
import IOKit
import IOKit.hidsystem

/// What a key does while hyper is held, instead of sending Hyper+key.
enum LayerAction {
    /// Send another key with these modifiers added (physical modifiers like Shift are
    /// kept, so Hyper+Shift+H selects to the left).
    case key(CGKeyCode, CGEventFlags)
    /// Toggle Caps Lock, since Caps Lock itself is now the hyper key.
    case toggleCapsLock
}

/// Layer keys that can be switched on and off individually from the menu.
enum LayerOption: String, CaseIterable {
    case spaceSwitchesInput
    case escTogglesCapsLock

    var title: String {
        switch self {
        case .spaceSwitchesInput: "Caps Lock + Space Switches Input"
        case .escTogglesCapsLock: "Caps Lock + Esc Toggles Caps Lock"
        }
    }

    /// Space is off by default: Hyper+Space is a common launcher shortcut (e.g. Raycast).
    var isOnByDefault: Bool { self == .escTogglesCapsLock }

    var defaultsKey: String { "option.\(rawValue)" }
}

enum NavigationLayer {
    struct Entry {
        let keyCode: Int64
        let key: String          // label on the physical key
        let action: LayerAction
        let description: String
        /// Entries with an option only apply while that option is turned on in the menu,
        /// because they can clash with Hyper shortcuts people already use.
        var option: LayerOption? = nil
    }

    struct Group {
        let title: String
        let entries: [Entry]
    }

    // Flags macOS sets on real arrow / navigation key events. Some apps check them.
    private static let arrow: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]
    private static let nav: CGEventFlags = .maskSecondaryFn

    /// The layer, grouped for display. Keys not listed here keep the plain Hyper behavior.
    static let groups: [Group] = [
        Group(title: "Arrows", entries: [
            Entry(keyCode: 4, key: "H", action: .key(123, arrow), description: "Left"),
            Entry(keyCode: 38, key: "J", action: .key(125, arrow), description: "Down"),
            Entry(keyCode: 40, key: "K", action: .key(126, arrow), description: "Up"),
            Entry(keyCode: 37, key: "L", action: .key(124, arrow), description: "Right"),
        ]),
        Group(title: "Jump", entries: [
            Entry(keyCode: 41, key: ";", action: .key(123, arrow.union(.maskAlternate)), description: "Word back"),
            Entry(keyCode: 39, key: "'", action: .key(124, arrow.union(.maskAlternate)), description: "Word forward"),
            Entry(keyCode: 34, key: "I", action: .key(123, arrow.union(.maskCommand)), description: "Line start"),
            Entry(keyCode: 31, key: "O", action: .key(124, arrow.union(.maskCommand)), description: "Line end"),
            Entry(keyCode: 32, key: "U", action: .key(116, nav), description: "Page up"),
            Entry(keyCode: 35, key: "P", action: .key(121, nav), description: "Page down"),
        ]),
        Group(title: "Other", entries: [
            Entry(keyCode: 49, key: "Space", action: .key(49, .maskControl), description: "Switch input source",
                  option: .spaceSwitchesInput),
            Entry(keyCode: 53, key: "Esc", action: .toggleCapsLock, description: "Toggle Caps Lock",
                  option: .escTogglesCapsLock),
        ]),
    ]

    private static let entries: [Int64: Entry] = Dictionary(
        uniqueKeysWithValues: groups.flatMap(\.entries).map { ($0.keyCode, $0) })

    static func action(for keyCode: Int64, options: Set<LayerOption>) -> LayerAction? {
        guard let entry = entries[keyCode] else { return nil }
        if let option = entry.option, !options.contains(option) { return nil }
        return entry.action
    }

    static func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }

        var state = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state)
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !state)
    }
}
