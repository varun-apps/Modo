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
    @Published var activeMode: Mode?
    @Published var isStreaming = false {
        didSet {
            if oldValue != isStreaming {
                NotificationCenter.default.post(
                    name: Self.isStreamingDidChangeNotification, object: isStreaming)
            }
        }
    }

    static let isStreamingDidChangeNotification = Notification.Name("Modo.isStreamingDidChange")
    @Published var errorMessage: String?
    @Published var replaceNotice: String?
    @Published var hasAccessibilityPermission: Bool = AXIsProcessTrusted()
    @Published var customModes: [Mode] = CustomModeStore.shared.load()
    @Published var lastUsedModeID: String? = UserDefaults.standard.string(forKey: lastUsedModeKey)
    @Published var detectedTone: String?

    private static let lastUsedModeKey = "lastUsedModeID"
    private static let toneDetectionEnabledKey = "toneDetectionEnabled"

    static var isToneDetectionEnabled: Bool {
        get { UserDefaults.standard.object(forKey: toneDetectionEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: toneDetectionEnabledKey) }
    }

    private static let toneDetectionMode: Mode = Mode.custom(
        id: "internal.toneDetection",
        title: "Tone",
        systemSymbol: "waveform",
        systemPrompt: "Describe in one short sentence (under 14 words) how the text inside <text> tags reads in tone. " +
                      "Examples: \"This sounds blunt and direct.\" \"This reads as friendly and conversational.\" " +
                      "\"This is formal and professional.\" " +
                      "Return ONLY that one sentence. No preamble, no quotes, no labels.",
        isDirectPrompt: false
    )

    private var toneTask: Task<Void, Never>?

    /// All modes shown in the popover: built-ins first, then user custom modes.
    var availableModes: [Mode] {
        Mode.allBuiltIn + customModes
    }

    var lastUsedMode: Mode? {
        guard let id = lastUsedModeID else { return nil }
        return availableModes.first { $0.id == id }
    }

    /// Re-reads custom modes from disk (call after the user edits them in Preferences).
    func reloadCustomModes() {
        customModes = CustomModeStore.shared.load()
    }

    /// True when there is no usable selection to act on.
    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAPIKey: Bool {
        let provider = AIProvider.current
        if !provider.requiresAPIKey { return true }
        return KeychainService.hasKey(for: provider.keychainAccount)
    }

    private var streamTask: Task<Void, Never>?
    private var permissionTimer: Timer?

    /// Resolves the (service, modelOverride) tuple for a mode, honoring any
    /// stored per-mode override. If `oneShotModelOverride` is supplied (e.g. by
    /// "Try a different model"), it wins over both per-mode and default.
    private static func resolveService(forModeID modeID: String,
                                       oneShotModelOverride: String? = nil) -> (AIProviderService, String?) {
        if let oneShot = oneShotModelOverride {
            let provider = AIProvider.current
            return (provider.makeService(), oneShot)
        }
        if let override = ModeOverridesStore.shared.override(for: modeID) {
            let provider: AIProvider
            if let raw = override.providerRaw, let p = AIProvider(rawValue: raw) {
                provider = p
            } else {
                provider = AIProvider.current
            }
            return (provider.makeService(), override.modelID)
        }
        let provider = AIProvider.current
        return (provider.makeService(), nil)
    }

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

    /// Replaces the current selection in memory (used by drag-and-drop).
    /// Doesn't read from the source app — just uses the supplied string.
    func replaceSelection(with text: String) {
        cancelStreaming()
        cancelToneDetection()
        detectedTone = nil
        screen = .modeSelection
        resultText = ""
        errorMessage = nil
        replaceNotice = nil
        activeMode = nil
        selectedText = text
        if Self.isToneDetectionEnabled {
            detectTone()
        }
    }

    /// Called each time the window opens: re-read the current selection.
    func refreshSelection() {
        cancelStreaming()
        cancelToneDetection()
        detectedTone = nil
        screen = .modeSelection
        resultText = ""
        errorMessage = nil
        replaceNotice = nil
        activeMode = nil
        reloadCustomModes()
        selectedText = AccessibilityService.shared.readSelectedText() ?? ""
        if Self.isToneDetectionEnabled {
            detectTone()
        }
    }

    /// Kick off a small background API call that asks the model how the
    /// selected text reads in tone. Best-effort; failures are silent.
    ///
    /// We debounce by ~400ms so quickly-dismissed popovers don't consume
    /// tokens, and bail out the moment the user starts a real rewrite so the
    /// two streams don't race for rate-limit budget.
    private func detectTone() {
        guard hasSelection, hasAPIKey else { return }
        let textToAnalyze = selectedText
        toneTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 400_000_000) // debounce
            if Task.isCancelled { return }
            // If the user already picked a mode, skip tone detection.
            if self.isStreaming || self.screen == .result { return }

            var tone = ""
            do {
                try await AIProvider.current.makeService().streamImprovement(
                    text: textToAnalyze, mode: Self.toneDetectionMode
                ) { delta in
                    tone += delta
                }
                if !Task.isCancelled {
                    let cleaned = Self.clampToneOutput(tone)
                    if !cleaned.isEmpty {
                        self.detectedTone = cleaned
                    }
                }
            } catch {
                // best-effort
            }
        }
    }

    /// Trim a possibly-multiline LLM reply down to a single short sentence
    /// suitable for the small tone badge.
    private static func clampToneOutput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let limit = 140
        if firstLine.count <= limit { return firstLine }
        return String(firstLine.prefix(limit)) + "…"
    }

    private func cancelToneDetection() {
        toneTask?.cancel()
        toneTask = nil
    }

    /// Public entry point so the window controller can cancel a tone-detection
    /// task that's still in flight when the popover closes — otherwise the
    /// background API call keeps streaming after dismissal.
    func cancelToneDetectionPublic() {
        cancelToneDetection()
    }

    /// Begin improving the selection with the chosen mode.
    /// Pass `oneShotModelOverride` to run with a specific model just this once
    /// (e.g. "Try a different model" on the result screen).
    func run(mode: Mode, oneShotModelOverride: String? = nil) {
        guard hasSelection else { return }
        guard hasAPIKey else {
            screen = .result
            errorMessage = "Add your API key in Preferences."
            return
        }

        activeMode = mode
        lastUsedModeID = mode.id
        UserDefaults.standard.set(mode.id, forKey: Self.lastUsedModeKey)
        screen = .result
        resultText = ""
        errorMessage = nil
        replaceNotice = nil
        isStreaming = true

        let textToImprove = selectedText
        let (service, modelOverride) = Self.resolveService(forModeID: mode.id,
                                                           oneShotModelOverride: oneShotModelOverride)
        streamTask = Task { [weak self] in
            guard let self else { return }
            var completedSuccessfully = false

            // Watchdog: if no delta arrives within the timeout, treat the
            // request as hung and surface a clear error rather than spinning
            // forever. Reset on each delta so long-but-progressing replies
            // are not killed mid-stream.
            let watchdog = StreamWatchdog(timeoutSeconds: 45) { [weak self] in
                Task { @MainActor [weak self] in self?.streamTask?.cancel() }
            }
            await watchdog.start()

            do {
                try await service.streamImprovement(
                    text: textToImprove, mode: mode, modelOverride: modelOverride
                ) { delta in
                    Task { await watchdog.tick() }
                    self.resultText += delta
                }
                completedSuccessfully = true
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                } else if await watchdog.firedTimeout {
                    self.errorMessage = "The provider stopped responding. Check your connection or try a different model."
                }
            }
            await watchdog.cancel()
            self.isStreaming = false
            if completedSuccessfully && !self.resultText.isEmpty {
                HistoryStore.shared.add(HistoryEntry(
                    modeTitle: mode.title,
                    modeSymbol: mode.systemSymbol,
                    originalText: textToImprove,
                    resultText: self.resultText
                ))
            }
        }
    }

    func retry() {
        if let mode = activeMode { run(mode: mode) }
    }

    /// Re-runs the active mode, optionally with a one-shot model override
    /// (used by "Try a different model" on the result screen).
    func regenerate(modelOverride: String? = nil) {
        if let mode = activeMode { run(mode: mode, oneShotModelOverride: modelOverride) }
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
        let originalSelection = selectedText
        let outcome = AccessibilityService.shared.replaceSelectedText(with: resultText)
        switch outcome {
        case .replacedInPlace:
            lastReplacedOriginal = originalSelection
            armUndoTimer()
            return true
        case .pastedViaClipboard:
            lastReplacedOriginal = originalSelection
            armUndoTimer()
            return true
        case .accessibilityRevoked:
            copyResult()
            replaceNotice = "Accessibility permission is off — result copied to clipboard. Re-enable Modo in System Settings → Privacy & Security → Accessibility."
            return false
        case .failed:
            copyResult()
            replaceNotice = "Couldn't replace — text copied to clipboard instead."
            return false
        }
    }

    // MARK: - Undo Replace

    @Published var lastReplacedOriginal: String?
    private var undoTimer: Timer?

    private func armUndoTimer() {
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.lastReplacedOriginal = nil }
        }
    }

    /// Reverts the last successful Replace by pasting the original text back.
    /// The popover must still be open (we keep the original in memory for ~30s).
    func undoReplace() -> Bool {
        guard let original = lastReplacedOriginal else { return false }
        let outcome = AccessibilityService.shared.replaceSelectedText(with: original)
        lastReplacedOriginal = nil
        undoTimer?.invalidate()
        return outcome == .replacedInPlace || outcome == .pastedViaClipboard
    }
}
