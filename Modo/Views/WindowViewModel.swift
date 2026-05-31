import SwiftUI

/// Drives the floating window UI. Holds the captured selection, the streaming
/// result, and the current screen (mode selection vs. result).
@MainActor
final class WindowViewModel: ObservableObject {

    enum Screen {
        case modeSelection
        case result
    }

    @Published var screen: Screen = .modeSelection
    @Published var selectedText: String = ""
    @Published var resultText: String = ""
    @Published var activeMode: ImprovementMode?
    @Published var isStreaming = false
    @Published var errorMessage: String?
    @Published var replaceNotice: String?
    @Published var hasAccessibilityPermission: Bool = AXIsProcessTrusted()

    /// True when there is no usable selection to act on.
    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAPIKey: Bool { KeychainService.hasKey(for: AIProvider.current.keychainAccount) }

    private var streamTask: Task<Void, Never>?
    private var permissionTimer: Timer?

    init() {
        // Poll every second while the permission is not yet granted so the UI
        // updates automatically when the user returns from System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if self.hasAccessibilityPermission != trusted {
                    self.hasAccessibilityPermission = trusted
                }
                // Stop polling once permission is granted.
                if trusted {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    /// Called each time the window opens: re-read the current selection.
    func refreshSelection() {
        cancelStreaming()
        screen = .modeSelection
        resultText = ""
        errorMessage = nil
        replaceNotice = nil
        activeMode = nil
        selectedText = AccessibilityService.shared.readSelectedText() ?? ""
    }

    /// Begin improving the selection with the chosen mode.
    func run(mode: ImprovementMode) {
        guard hasSelection else { return }
        guard hasAPIKey else {
            screen = .result
            errorMessage = "Add your API key in Preferences."
            return
        }

        activeMode = mode
        screen = .result
        resultText = ""
        errorMessage = nil
        replaceNotice = nil
        isStreaming = true

        let textToImprove = selectedText
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await AIProvider.current.makeService().streamImprovement(
                    text: textToImprove, mode: mode
                ) { delta in
                    self.resultText += delta
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
            self.isStreaming = false
        }
    }

    func retry() {
        if let mode = activeMode { run(mode: mode) }
    }

    func back() {
        cancelStreaming()
        screen = .modeSelection
        resultText = ""
        errorMessage = nil
        replaceNotice = nil
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    /// Copy the result to the clipboard.
    func copyResult() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resultText, forType: .string)
    }

    /// Try to replace the original selection; fall back to clipboard on failure.
    /// Returns true if the window should close.
    func replaceResult() -> Bool {
        let ok = AccessibilityService.shared.replaceSelectedText(with: resultText)
        if ok {
            return true
        } else {
            copyResult()
            replaceNotice = "Couldn't replace — text copied to clipboard instead."
            return false
        }
    }
}
