import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// Remaps Caps Lock to F18 on every keyboard at the HID event system level.
///
/// This is what `hidutil property --set UserKeyMapping` does, but done in-process and
/// per keyboard service, so it can be re-applied whenever a keyboard is connected or
/// the system drops the mapping (sleep/wake, Bluetooth reconnects, other remappers).
/// Existing user mappings for other keys are preserved.
final class KeyRemapper {
    struct Keyboard: Equatable {
        let name: String
        let isBuiltIn: Bool
        let transport: String
    }

    static let capsLockUsage: UInt64 = 0x7_0000_0039
    static let f18Usage: UInt64 = 0x7_0000_006D

    private static let mappingProperty = "UserKeyMapping" as CFString
    private static let srcKey = "HIDKeyboardModifierMappingSrc"
    private static let dstKey = "HIDKeyboardModifierMappingDst"

    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var timer: Timer?

    private(set) var keyboards: [Keyboard] = []
    /// Number of times a mapping had to be re-applied after it went missing.
    private(set) var repairCount = 0

    func start() {
        apply()
        observeDevices()
        // Safety net: the system can silently reset UserKeyMapping.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.apply()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        iterators.forEach { IOObjectRelease($0) }
        iterators.removeAll()
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        for service in keyboardServices() {
            setMappings(currentMappings(service).filter { !isOurs($0) }, on: service)
        }
        log("restored Caps Lock on all keyboards")
    }

    /// Ensures every keyboard has the Caps Lock -> F18 mapping. Cheap when nothing changed.
    func apply() {
        var found: [Keyboard] = []
        for service in keyboardServices() {
            let keyboard = describe(service)
            let mappings = currentMappings(service)
            if !mappings.contains(where: isOurs) {
                var updated = mappings.filter { usage($0[Self.srcKey]) != Self.capsLockUsage }
                updated.append([Self.srcKey: Self.capsLockUsage, Self.dstKey: Self.f18Usage])
                if setMappings(updated, on: service) {
                    if keyboards.contains(keyboard) { repairCount += 1 }
                    log("mapped Caps Lock on \(keyboard.name)")
                } else {
                    log("failed to map Caps Lock on \(keyboard.name)")
                }
            }
            if !found.contains(keyboard) { found.append(keyboard) }
        }
        keyboards = found
    }

    // MARK: - Device notifications

    private func observeDevices() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching(kIOHIDDeviceKey), deviceChanged, context, &iterator)
            guard result == KERN_SUCCESS else { continue }
            drain(iterator)
            iterators.append(iterator)
        }
    }

    fileprivate func devicesChanged() {
        // The HID event service for a new device shows up shortly after the device itself.
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.apply() }
    }

    // MARK: - HID event system helpers

    private func keyboardServices() -> [IOHIDServiceClient] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return services.filter {
            IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0
        }
    }

    private func describe(_ service: IOHIDServiceClient) -> Keyboard {
        let name = property(kIOHIDProductKey, of: service) as? String ?? "Unknown keyboard"
        let transport = property(kIOHIDTransportKey, of: service) as? String ?? ""
        let builtIn = (property(kIOHIDBuiltInKey, of: service) as? Bool) ?? false
        return Keyboard(name: name, isBuiltIn: builtIn || transport == "SPI", transport: transport)
    }

    private func property(_ key: String, of service: IOHIDServiceClient) -> Any? {
        IOHIDServiceClientCopyProperty(service, key as CFString)
    }

    private func currentMappings(_ service: IOHIDServiceClient) -> [[String: Any]] {
        IOHIDServiceClientCopyProperty(service, Self.mappingProperty) as? [[String: Any]] ?? []
    }

    @discardableResult
    private func setMappings(_ mappings: [[String: Any]], on service: IOHIDServiceClient) -> Bool {
        IOHIDServiceClientSetProperty(service, Self.mappingProperty, mappings as CFArray)
    }

    private func isOurs(_ mapping: [String: Any]) -> Bool {
        usage(mapping[Self.srcKey]) == Self.capsLockUsage && usage(mapping[Self.dstKey]) == Self.f18Usage
    }

    private func usage(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}

private func drain(_ iterator: io_iterator_t) {
    while case let object = IOIteratorNext(iterator), object != 0 {
        IOObjectRelease(object)
    }
}

/// IOKit notification callback. Must be a plain C function, so it gets the remapper via refcon.
private func deviceChanged(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    drain(iterator)
    guard let refcon else { return }
    Unmanaged<KeyRemapper>.fromOpaque(refcon).takeUnretainedValue().devicesChanged()
}
