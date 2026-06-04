import AppKit
import SwiftUI

/// Manages the popover that drops down from the status bar icon.
/// NSPopover is purpose-built for menu bar apps and handles positioning,
/// dismissal, and window-level correctly without custom hacks.
@MainActor
final class FloatingWindowController: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    let viewModel = WindowViewModel()
    private var resignObserver: Any?
    private var keyMonitor: Any?

    override init() {
        super.init()
        // NSWorkspace.didActivateApplicationNotification fires whenever any app
        // comes to the front — including Cmd+Tab switches — which is more
        // reliable than didResignActiveNotification for accessory (LSUIElement) apps.
        // We deliberately filter out our OWN activation so opening Preferences
        // or Help doesn't trigger a redundant popover close while AppKit is
        // mid-teardown of a transient popover's click-outside tap.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        resignObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activated?.processIdentifier != ownPID else { return }
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    deinit {
        if let resignObserver { NSWorkspace.shared.notificationCenter.removeObserver(resignObserver) }
    }

    func toggle(relativeTo statusButton: NSStatusBarButton) {
        if let popover, popover.isShown {
            close()
        } else {
            show(relativeTo: statusButton)
        }
    }

    /// Opens the popover and immediately runs the mode with the given id,
    /// streaming the result into the result screen. Used by per-mode hotkeys.
    func openAndRun(modeID: String, relativeTo statusButton: NSStatusBarButton) {
        show(relativeTo: statusButton)
        guard let mode = viewModel.availableModes.first(where: { $0.id == modeID }) else { return }
        viewModel.run(mode: mode)
    }

    private func show(relativeTo statusButton: NSStatusBarButton) {
        // Read selection BEFORE the popover appears so the source app's
        // focused element is still accessible via Accessibility API.
        viewModel.refreshSelection()

        // Always build a fresh popover instead of reusing a cached one. This
        // guarantees AppKit's transient click-outside event tap is created
        // and torn down 1:1 with our popover lifecycle. Reusing a popover
        // across show/close cycles has caused stuck system-wide event taps
        // on some macOS versions.
        let popover = makePopover()
        self.popover = popover

        popover.show(relativeTo: statusButton.bounds,
                     of: statusButton,
                     preferredEdge: .minY)

        installKeyMonitor()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        let content = FloatingPanelContentView(viewModel: viewModel) { [weak self] in
            self?.close()
        }
        popover.contentViewController = NSHostingController(rootView: content)
        popover.contentSize = NSSize(width: 340, height: 300)
        popover.behavior = .transient  // closes on click-outside automatically
        popover.animates = true
        popover.delegate = self
        return popover
    }

    func close() {
        viewModel.cancelStreaming()
        viewModel.cancelToneDetectionPublic()
        removeKeyMonitor()
        if let popover {
            // Force the underlying NSPanel off-screen first. NSPopover renders
            // inside a high-level panel; if its close animation doesn't
            // complete cleanly (race during app switching, content swap, etc.)
            // the panel can linger invisibly on top of every other app and
            // silently absorb clicks. orderOut bypasses the animation and
            // removes the window immediately.
            popover.contentViewController?.view.window?.orderOut(nil)
            popover.close()
        }
        popover = nil
        // Return focus to whatever app the user was working in. Without this,
        // dismissing the popover can leave the user in a no-app-focused state.
        AccessibilityService.shared.reactivateSourceApp()
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Escape — close the popover. SwiftUI's .keyboardShortcut(.escape)
            // doesn't reach popovers consistently, so we handle it here.
            if event.keyCode == 53 { // kVK_Escape
                Task { @MainActor [weak self] in self?.close() }
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        viewModel.cancelStreaming()
        viewModel.cancelToneDetectionPublic()
        removeKeyMonitor()
        // Belt-and-braces: even on a "normal" close path, force the underlying
        // panel out so it can't linger as an invisible overlay swallowing
        // clicks meant for other apps.
        if let panel = (notification.object as? NSPopover)?.contentViewController?.view.window {
            panel.orderOut(nil)
        }
        popover = nil
        AccessibilityService.shared.reactivateSourceApp()
    }
}
