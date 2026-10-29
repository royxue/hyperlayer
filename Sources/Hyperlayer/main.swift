import AppKit
import os

private let logger = Logger(subsystem: "com.royxue.hyperlayer", category: "app")

/// Logs to stderr and the unified log, so problems can be traced after the fact with
/// `log show --last 1d --predicate 'subsystem == "com.royxue.hyperlayer"'`.
func log(_ message: String) {
    FileHandle.standardError.write(Data("hyperlayer: \(message)\n".utf8))
    logger.notice("\(message, privacy: .public)")
}

let bundleID = Bundle.main.bundleIdentifier ?? "com.royxue.hyperlayer"

if CommandLine.arguments.contains("--version") {
    print("Hyperlayer \(AppDelegate.version)")
    exit(0)
}

if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    log("already running")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
