import AppKit

/// Ensures only one copy of Modo runs at a time. The global hotkey and the
/// selection event monitor must have a single owner — a second instance would
/// fight the first for the hotkey registration and double-show panels.
///
/// Call `anotherInstanceIsRunning()` at the very start of
/// `applicationDidFinishLaunching`; if it returns true, hand control to the
/// existing instance and terminate this one.
enum SingleInstanceGuard {
    static func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }
        guard let existing = others.first else { return false }
        // Surface the already-running instance so the user sees a response to
        // their (re)launch instead of nothing happening.
        existing.activate(options: [.activateAllWindows])
        return true
    }
}
