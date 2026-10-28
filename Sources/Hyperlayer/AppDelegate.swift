import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    private let settings = Settings()
    private let remapper = KeyRemapper()
    private lazy var hyperKey = HyperKey(settings: settings)
    private let keyMapOverlay = KeyMapOverlay()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        handleTerminationSignals()
        remapper.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.remapper.apply()
        }

        startWhenTrusted()
    }

    func applicationWillTerminate(_ notification: Notification) {
        remapper.stop()
    }

    // MARK: - Accessibility

    /// Prompts for Accessibility access once, then polls (without blocking the main
    /// thread) until it is granted and the event tap can be installed.
    private func startWhenTrusted() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt), hyperKey.start() { return }

        log("waiting for Accessibility access")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.hyperKey.start() else { return }
            timer.invalidate()
            self.permissionTimer = nil
        }
    }

    // MARK: - Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // MenuBarIcon only exists inside the app bundle; fall back to a symbol for `swift run`.
        let icon = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "capslock.fill", accessibilityDescription: nil)
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        icon?.accessibilityDescription = "Hyperlayer"
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt on every open so status (permissions, keyboards, Secure Input) is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabled("Hyperlayer \(Self.version)"))

        if !hyperKey.isRunning {
            menu.addItem(item("⚠︎ Grant Accessibility Access…", #selector(openAccessibilitySettings)))
        }
        if IsSecureEventInputEnabled() {
            menu.addItem(disabled("⚠︎ Secure Input is on, hyper is paused"))
        }
        menu.addItem(.separator())

        menu.addItem(item("Key Mapping…", #selector(showKeyMapping)))
        menu.addItem(toggle("Navigation Layer", #selector(toggleLayer), on: settings.layerEnabled))
        menu.addItem(keyboardsItem())
        menu.addItem(.separator())

        menu.addItem(toggle("Launch at Login", #selector(toggleLaunchAtLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        let quit = item("Quit Hyperlayer", #selector(NSApplication.terminate(_:)))
        quit.target = NSApp
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func keyboardsItem() -> NSMenuItem {
        remapper.apply()
        let submenu = NSMenu()
        if remapper.keyboards.isEmpty {
            submenu.addItem(disabled("No keyboards found"))
        }
        for keyboard in remapper.keyboards {
            let kind = keyboard.isBuiltIn ? "Built-in" : keyboard.transport
            submenu.addItem(disabled(kind.isEmpty ? keyboard.name : "\(keyboard.name) (\(kind))"))
        }
        let parent = NSMenuItem(title: "Keyboards", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggle(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let item = item(title, action)
        item.state = on ? .on : .off
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func showKeyMapping() {
        keyMapOverlay.toggle(settings: settings)
    }

    @objc private func toggleLayer() {
        settings.layerEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log("launch at login: \(error.localizedDescription)")
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Signals

    /// Restore Caps Lock when killed from the terminal or by launchd, not just via Quit.
    private func handleTerminationSignals() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}
