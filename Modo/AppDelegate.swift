import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let windowController = FloatingWindowController()
    private var preferencesWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var streamingPulseTimer: Timer?
    private var streamingObserver: NSObjectProtocol?
    private var helpObserver: NSObjectProtocol?
    // Hold a strong reference so Sparkle's background scheduler keeps running
    // for the life of the app.
    private let updaterService = UpdaterService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, no main menu. (Also enforced by
        // LSUIElement in Info.plist, but we set it here for safety.)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupGlobalHotkey()
        setupHelpListener()

        // On first launch, show the in-app onboarding flow which walks the
        // user through API key + Accessibility setup. Otherwise fall back to
        // the lightweight permission alert.
        if !OnboardingView.hasCompleted {
            openOnboarding()
        } else {
            AccessibilityService.shared.promptForPermissionIfNeeded()
        }
    }

    private func setupHelpListener() {
        helpObserver = NotificationCenter.default.addObserver(
            forName: .openModoHelp, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.openHelp() }
        }
    }

    private func setupGlobalHotkey() {
        HotkeyService.shared.globalCallback = { [weak self] in
            self?.toggleFloatingWindow()
        }
        HotkeyService.shared.modeCallback = { [weak self] modeID in
            self?.openAndRun(modeID: modeID)
        }
        HotkeyService.shared.register()
    }

    private func openAndRun(modeID: String) {
        guard let button = statusItem.button else { return }
        windowController.openAndRun(modeID: modeID, relativeTo: button)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Receive both left and right mouse-up events.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // Native macOS tooltip — appears after a short hover.
            button.toolTip = "Modo — click to rewrite the selected text. Right-click for Preferences, History, and Help."
        }

        // Pulse the menu-bar icon while a stream is in flight so users on
        // slow networks can see that Modo is still working.
        streamingObserver = NotificationCenter.default.addObserver(
            forName: WindowViewModel.isStreamingDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let streaming = (note.object as? Bool) ?? false
            Task { @MainActor [weak self] in
                self?.setStreamingPulse(streaming)
            }
        }
    }

    private func setStreamingPulse(_ streaming: Bool) {
        streamingPulseTimer?.invalidate()
        streamingPulseTimer = nil
        guard let button = statusItem?.button else { return }

        if streaming {
            var dim = false
            streamingPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak button] _ in
                guard let button else { return }
                dim.toggle()
                button.animator().alphaValue = dim ? 0.45 : 1.0
            }
        } else {
            button.animator().alphaValue = 1.0
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp ||
            (event?.modifierFlags.contains(.control) ?? false) {
            showContextMenu()
        } else {
            toggleFloatingWindow()
        }
    }

    private func toggleFloatingWindow() {
        guard let button = statusItem.button else { return }
        windowController.toggle(relativeTo: button)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences…",
                                action: #selector(openPreferences),
                                keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "History…",
                                action: #selector(openHistory),
                                keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Help…",
                                action: #selector(openHelp),
                                keyEquivalent: ""))

        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…",
                                             action: #selector(checkForUpdates),
                                             keyEquivalent: "")
        checkForUpdatesItem.isEnabled = updaterService.canCheckForUpdates
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Modo",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        // Temporarily attach the menu so it pops from the status item, then
        // detach so left-clicks still trigger our action.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let hosting = NSHostingController(rootView: PreferencesView())
            hosting.view.setFrameSize(NSSize(width: 480, height: 820))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Preferences"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 480, height: 820))
            preferencesWindow = window
        }
        presentUtilityWindow(preferencesWindow)
    }

    private func openOnboarding() {
        if onboardingWindow == nil {
            let hosting = NSHostingController(rootView: OnboardingView(onFinish: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }))
            hosting.view.setFrameSize(NSSize(width: 520, height: 480))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to Modo"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 480))
            onboardingWindow = window
        }
        presentUtilityWindow(onboardingWindow)
    }

    @objc private func checkForUpdates() {
        updaterService.checkForUpdates()
    }

    @objc private func openHelp() {
        if helpWindow == nil {
            let hosting = NSHostingController(rootView: HelpView())
            hosting.view.setFrameSize(NSSize(width: 820, height: 600))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Modo Help"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 820, height: 600))
            helpWindow = window
        }
        presentUtilityWindow(helpWindow)
    }

    @objc private func openHistory() {
        if historyWindow == nil {
            let hosting = NSHostingController(rootView: HistoryView())
            hosting.view.setFrameSize(NSSize(width: 720, height: 460))
            let window = NSWindow(contentViewController: hosting)
            window.title = "History"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 720, height: 460))
            historyWindow = window
        }
        presentUtilityWindow(historyWindow)
    }

    /// Centralized presenter for our utility windows (Preferences, History,
    /// Help, Onboarding). Closes the popover first so it doesn't compete for
    /// focus, then defers activation to the next runloop turn so the
    /// status-item context menu that triggered us has fully torn down.
    /// Without this, the window can appear but stay non-key, which makes
    /// SwiftUI Lists/sidebars render as if disabled.
    private func presentUtilityWindow(_ window: NSWindow?) {
        guard let window else { return }
        windowController.close()
        positionOnActiveScreen(window)
        DispatchQueue.main.async {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Centers `window` on the screen containing the mouse pointer (falling
    /// back to the main screen). Without this, `window.center()` always uses
    /// the primary display, which can leave the window off-screen on a
    /// secondary monitor.
    private func positionOnActiveScreen(_ window: NSWindow?) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }
}
