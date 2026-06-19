import AppKit
import SwiftUI

/// Hosts the `SelectionOverlayView` inside a borderless, non-activating
/// `NSPanel` that floats above other apps. Listens to `SelectionMonitor` so
/// the overlay appears next to any text selection and disappears the moment
/// the selection goes away.
///
/// The user enables this in Preferences. When the preference is off,
/// `stop()` shuts everything down.
@MainActor
final class SelectionOverlayController: NSObject {
    static let enabledKey = "selectionOverlay_enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    /// Called when the user clicks the overlay. Receivers should open the
    /// regular Modo popover with the current selection.
    var onActivate: (() -> Void)?

    private var panel: NSPanel?
    private var observer: NSObjectProtocol?
    private var isRunning = false

    override init() {
        super.init()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observer = NotificationCenter.default.addObserver(
            forName: SelectionMonitor.selectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleSelectionChange(note.object as? SelectionMonitor.Selection)
            }
        }
        SelectionMonitor.shared.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        SelectionMonitor.shared.stop()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        hidePanel()
    }

    // MARK: - Notification handling

    private func handleSelectionChange(_ selection: SelectionMonitor.Selection?) {
        guard let selection else {
            hidePanel()
            return
        }
        showPanel(for: selection)
    }

    // MARK: - Panel management

    private func showPanel(for selection: SelectionMonitor.Selection) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let size = NSSize(width: 84, height: 30)
        // Place the pill just below-right of the selection's bottom-right.
        var origin = NSPoint(
            x: selection.bounds.maxX + 6,
            y: selection.bounds.minY - size.height - 6
        )

        // If the placement falls off the current screen, snap it back inside.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(
            x: selection.bounds.midX, y: selection.bounds.midY)) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX + 4), f.maxX - size.width - 4)
            origin.y = min(max(origin.y, f.minY + 4), f.maxY - size.height - 4)
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingController(rootView: SelectionOverlayView { [weak self] in
            self?.hidePanel()
            self?.onActivate?()
        })
        host.view.setFrameSize(NSSize(width: 84, height: 30))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 84, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = host
        return panel
    }
}
