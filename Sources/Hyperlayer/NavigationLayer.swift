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

enum NavigationLayer {
    // Flags macOS sets on real arrow / navigation key events. Some apps check them.
    private static let arrow: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]
    private static let nav: CGEventFlags = .maskSecondaryFn

    /// Virtual keycode -> action. Keys not listed here keep the plain Hyper behavior.
    static let mappings: [Int64: LayerAction] = [
        4: .key(123, arrow),                            // H -> Left
        38: .key(125, arrow),                           // J -> Down
        40: .key(126, arrow),                           // K -> Up
        37: .key(124, arrow),                           // L -> Right
        41: .key(123, arrow.union(.maskAlternate)),     // ; -> Opt+Left (word back)
        39: .key(124, arrow.union(.maskAlternate)),     // ' -> Opt+Right (word forward)
        34: .key(123, arrow.union(.maskCommand)),       // I -> Cmd+Left (line start)
        31: .key(124, arrow.union(.maskCommand)),       // O -> Cmd+Right (line end)
        32: .key(116, nav),                             // U -> Page Up
        35: .key(121, nav),                             // P -> Page Down
        49: .key(49, .maskControl),                     // Space -> Ctrl+Space (input source)
        53: .toggleCapsLock,                            // Esc -> Caps Lock
    ]

    static func action(for keyCode: Int64) -> LayerAction? {
        mappings[keyCode]
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
