import AppKit

/// Watches for text selections in the user's other apps. When a non-empty
/// selection appears (and the user is not currently in Modo itself), posts a
/// `selectionDidChangeNotification` so the floating overlay can show itself
/// near that selection.
///
/// Polls AX once per second on a **detached background task** with each AX
/// call capped at 250 ms by `AXUIElementSetMessagingTimeout`. This prevents
/// a slow or unresponsive target app from blocking Modo's main thread —
/// which would otherwise back up the WindowServer queue and delay focus
/// changes / clicks in unrelated apps.
@MainActor
final class SelectionMonitor {
    static let shared = SelectionMonitor()

    static let selectionDidChangeNotification = Notification.Name("Modo.SelectionDidChange")

    /// Posted as the notification's `object`. `nil` object means "no
    /// selection right now" (hide the overlay).
    struct Selection: Sendable {
        let text: String
        let bounds: CGRect  // AppKit coordinates (bottom-left origin)
        let appBundleID: String?
    }

    /// Apps where the overlay would be more annoying than helpful.
    private let suppressedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "co.zeit.hyper",
        Bundle.main.bundleIdentifier ?? ""
    ]

    private var pollTask: Task<Void, Never>?
    private var lastFingerprint: String?

    private init() {}

    func start() {
        guard pollTask == nil else { return }
        let suppressed = suppressedBundleIDs
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
                if Task.isCancelled { break }
                let result = Self.probe(suppressed: suppressed)
                await self?.broadcast(result)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        lastFingerprint = nil
        NotificationCenter.default.post(
            name: Self.selectionDidChangeNotification, object: nil)
    }

    // MARK: - Background probe

    /// Static + nonisolated so it can run on any thread. Does only AX +
    /// NSWorkspace reads — no instance state, no NSScreen access.
    private nonisolated static func probe(suppressed: Set<String>) -> Selection? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        if let bundleID = frontApp.bundleIdentifier, suppressed.contains(bundleID) {
            return nil
        }
        // Respect the user's per-app disable list and skip VM/remote windows.
        if !AppPolicy.shared.isEnabled(forBundleID: frontApp.bundleIdentifier) {
            return nil
        }
        if UnsupportedApps.isVMOrRemote(frontApp.bundleIdentifier) {
            return nil
        }
        guard let probe = AccessibilityService.peekSelectionWithBounds() else {
            return nil
        }
        return Selection(text: probe.text,
                         bounds: probe.bounds,
                         appBundleID: frontApp.bundleIdentifier)
    }

    /// Only post when the selection's text+bounds actually changed since the
    /// previous tick. Prevents the overlay from re-rendering / re-positioning
    /// every poll while the user is reading their own selection.
    private func broadcast(_ selection: Selection?) {
        let fingerprint: String?
        if let s = selection {
            fingerprint = "\(s.text.hashValue):\(s.bounds.origin.x),\(s.bounds.origin.y),\(s.bounds.size.width),\(s.bounds.size.height)"
        } else {
            fingerprint = nil
        }
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        NotificationCenter.default.post(
            name: Self.selectionDidChangeNotification,
            object: selection
        )
    }
}
