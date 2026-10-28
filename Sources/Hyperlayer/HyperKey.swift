import CoreGraphics
import Foundation

/// Turns F18 (which Caps Lock is remapped to by `KeyRemapper`) into a Hyper key.
///
/// While F18 is held, keys in the navigation layer are rewritten (H -> Left, ...) and
/// every other key gets Cmd+Ctrl+Opt+Shift added. A single event tap sees all keyboards,
/// built-in and external, so no device is ever seized and no events are re-injected.
final class HyperKey {
    static let hyperFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    private static let f18KeyCode: Int64 = 79
    private static let escapeKeyCode: CGKeyCode = 53

    /// Send Escape when Caps Lock is pressed and released without another key.
    var tapForEscape = false
    /// Apply `NavigationLayer` mappings while hyper is held.
    var layerEnabled = true

    private var tap: CFMachPort?
    private var isHeld = false
    private var wasUsed = false

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Installs the event tap. Fails if Accessibility access has not been granted.
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hyperKeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("could not create event tap (Accessibility access missing?)")
            return false
        }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        log("event tap started")
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // We may have missed the F18 key-up while disabled; don't leave hyper stuck on.
            if isHeld { log("event tap disabled while hyper was held, resetting") }
            isHeld = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if keyCode == Self.f18KeyCode && (type == .keyDown || type == .keyUp) {
            if type == .keyDown {
                if !isHeld {
                    isHeld = true
                    wasUsed = false
                }
            } else {
                release()
            }
            return nil
        }

        guard isHeld else { return pass }
        wasUsed = true

        if type == .flagsChanged {
            event.flags.formUnion(Self.hyperFlags)
            return pass
        }

        if layerEnabled, let action = NavigationLayer.action(for: keyCode) {
            switch action {
            case let .key(target, flags):
                // Keep physical modifiers (Shift+H selects left) but drop Caps Lock state.
                var newFlags = event.flags.subtracting(.maskAlphaShift)
                newFlags.formUnion(flags)
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(target))
                event.flags = newFlags
                return pass
            case .toggleCapsLock:
                if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    NavigationLayer.toggleCapsLock()
                }
                return nil
            }
        }

        event.flags.formUnion(Self.hyperFlags)
        return pass
    }

    private func release() {
        let tapped = isHeld && !wasUsed
        isHeld = false
        wasUsed = false
        if tapped && tapForEscape {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                CGEvent(keyboardEventSource: source, virtualKey: Self.escapeKeyCode, keyDown: down)?
                    .post(tap: .cghidEventTap)
            }
        }
    }
}

/// Event tap callback. Must be a plain C function, so it gets the HyperKey via userInfo.
private func hyperKeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HyperKey>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
