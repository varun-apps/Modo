import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let windowController = FloatingWindowController()
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, no main menu. (Also enforced by
        // LSUIElement in Info.plist, but we set it here for safety.)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        // Nudge the user toward granting Accessibility permission on first
        // launch. Non-blocking — they can grant it later from the alert.
        AccessibilityService.shared.promptForPermissionIfNeeded()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Receive both left and right mouse-up events.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
            hosting.view.setFrameSize(NSSize(width: 420, height: 340))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 420, height: 340))
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}
