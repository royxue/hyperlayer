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

    private let settings: Settings
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHeld = false
    private var wasUsed = false

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    init(settings: Settings) {
        self.settings = settings
    }

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
        runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        log("event tap started")
        return true
    }

    /// macOS can disable or invalidate the tap without the callback ever hearing about
    /// it (sleep, login, permission changes), leaving Caps Lock dead until a relaunch.
    /// Called periodically to bring it back.
    func ensureRunning() {
        guard let port = tap else { return }
        if !CFMachPortIsValid(port) {
            log("event tap was invalidated, recreating")
            if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
            tap = nil
            runLoopSource = nil
            isHeld = false
            _ = start()
        } else if !CGEvent.tapIsEnabled(tap: port) {
            log("event tap was disabled, re-enabling")
            isHeld = false
            CGEvent.tapEnable(tap: port, enable: true)
        }
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

        if settings.layerEnabled, let action = NavigationLayer.action(for: keyCode, options: settings.layerOptions) {
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
        if tapped && settings.tapForEscape {
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
