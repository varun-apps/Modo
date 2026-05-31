import AppKit
import SwiftUI

/// Manages the popover that drops down from the status bar icon.
/// NSPopover is purpose-built for menu bar apps and handles positioning,
/// dismissal, and window-level correctly without custom hacks.
@MainActor
final class FloatingWindowController: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private let viewModel = WindowViewModel()
    private var resignObserver: Any?

    override init() {
        super.init()
        // NSWorkspace.didActivateApplicationNotification fires whenever any app
        // comes to the front — including Cmd+Tab switches — which is more
        // reliable than didResignActiveNotification for accessory (LSUIElement) apps.
        resignObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.close()
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

    private func show(relativeTo statusButton: NSStatusBarButton) {
        // Read selection BEFORE the popover appears so the source app's
        // focused element is still accessible via Accessibility API.
        viewModel.refreshSelection()

        let popover = popover ?? makePopover()
        self.popover = popover

        popover.show(relativeTo: statusButton.bounds,
                     of: statusButton,
                     preferredEdge: .minY)
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
        popover?.close()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        viewModel.cancelStreaming()
    }
}
