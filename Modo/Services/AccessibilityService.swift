import AppKit
import ApplicationServices
import CoreGraphics

@inline(__always)
private func axLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[AX] \(message())")
#endif
}

/// Reads the currently selected text from any app and writes improved text
/// back. Uses a layered strategy so it works both with apps that expose the
/// Accessibility text APIs (TextEdit, Xcode, native NSTextViews) and with apps
/// that don't (Notes, Mail, many web-/Electron-based editors), where it falls
/// back to synthesizing ⌘C / ⌘V around the system pasteboard.
@MainActor
final class AccessibilityService {
    static let shared = AccessibilityService()
    private init() {}

    /// The focused UI element captured at read time, used later for Replace.
    private var focusedElement: AXUIElement?

    /// The app that owned the selection, so a paste-based Replace can
    /// reactivate it before synthesizing ⌘V.
    private var sourceApp: NSRunningApplication?

    /// Bundle ID of the source app, frozen at capture time. Used for the
    /// capability cache and content-free observability.
    private(set) var sourceBundleID: String?

    /// Where the most recent capture came from, so the apply chain can pick the
    /// matching write strategy.
    private var lastCaptureSource: CaptureSource?

    // Virtual key codes (ANSI layout). Modifier-based shortcuts are
    // layout-independent for C/V on every standard Mac keyboard.
    private let keyC: CGKeyCode = 0x08
    private let keyV: CGKeyCode = 0x09

    // MARK: - Permission

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// On first launch, if not trusted, ask macOS to show its native
    /// "<App> would like to control this computer" dialog. The system handles
    /// the Open System Settings path itself — we don't add a second NSAlert
    /// because doing so showed the user two back-to-back permission popups.
    func promptForPermissionIfNeeded() {
        guard !isTrusted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Reading selected text

    /// Back-compat thin wrapper: returns the selected text or nil. Prefer
    /// `captureSelection()` which distinguishes "nothing selected" from
    /// genuinely unsupported contexts.
    func readSelectedText() -> String? {
        if case let .text(text, _) = captureSelection() { return text }
        return nil
    }

    /// Reads the current selection, trying the cheapest, least intrusive method
    /// first and falling back to a clipboard copy for apps that don't expose
    /// the AX text attributes.
    ///
    /// Returns a `CaptureOutcome` so the caller can show an honest message:
    /// `.empty` (nothing selected), `.secureField` (password field active),
    /// `.unsupportedApp` (VM / remote desktop), `.nonText` (image selection),
    /// or `.text`. Provenance (`.accessibility` / `.clipboard`) is threaded
    /// through for the apply chain and the capability cache.
    func captureSelection() -> CaptureOutcome {
        let started = Date()
        axLog("captureSelection called, isTrusted=\(isTrusted)")
        focusedElement = nil
        lastCaptureSource = nil
        guard isTrusted else {
            axLog("aborting — accessibility not trusted")
            return .empty
        }

        // Secure-input guard: never touch AX or synthesize ⌘C while a password
        // field (or secure-keyboard-entry terminal) is focused anywhere.
        if SecureInput.isActive {
            axLog("secure input active; aborting")
            return .secureField
        }

        let front = NSWorkspace.shared.frontmostApplication
        sourceApp = front
        sourceBundleID = front?.bundleIdentifier
        axLog("frontmostApp: \(front?.localizedName ?? "nil")")

        // Per-app policy: respect the user's per-app disable list.
        if !AppPolicy.shared.isEnabled(forBundleID: sourceBundleID) {
            axLog("Modo disabled for \(sourceBundleID ?? "?")")
            return .disabledForApp
        }

        // Early bail for VM hosts / remote-desktop clients: their content is an
        // opaque image, so neither AX nor synthetic copy can read it.
        if UnsupportedApps.isVMOrRemote(sourceBundleID) {
            axLog("unsupported app (VM/remote): \(sourceBundleID ?? "?")")
            Observability.shared.logCapture(tier: nil, success: false,
                                            bundleID: sourceBundleID, latencyMS: 0)
            return .unsupportedApp
        }

        // Capability cache: if this app is known copy-only (Chromium/Electron),
        // skip the doomed AX attempt entirely to avoid latency + flicker.
        let preferClipboard = CapabilityCache.shared.preferredCaptureTier(for: sourceBundleID) == .clipboard

        if !preferClipboard {
            if let outcome = captureViaAX() {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                if case .text = outcome {
                    lastCaptureSource = .accessibility
                    CapabilityCache.shared.recordCapture(.accessibility, for: sourceBundleID)
                    Observability.shared.logCapture(tier: .accessibility, success: true,
                                                    bundleID: sourceBundleID, latencyMS: ms)
                }
                return outcome
            }
        }

        // Clipboard fallback (Notes, Mail, Word, web/Electron editors).
        let copy = selectionViaClipboardCopy()
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        switch copy {
        case .text(let text, _):
            lastCaptureSource = .clipboard
            CapabilityCache.shared.recordCapture(.clipboard, for: sourceBundleID)
            Observability.shared.logCapture(tier: .clipboard, success: true,
                                            bundleID: sourceBundleID, latencyMS: ms)
            return .text(text, source: .clipboard)
        case .nonText:
            Observability.shared.logCapture(tier: .clipboard, success: false,
                                            bundleID: sourceBundleID, latencyMS: ms)
            return .nonText
        default:
            Observability.shared.logCapture(tier: .clipboard, success: false,
                                            bundleID: sourceBundleID, latencyMS: ms)
            return .empty
        }
    }

    /// AX read path. Returns `.text` on success, `.empty` when AX is working
    /// but reports no selection (so the caller must NOT fall through to the ⌘C
    /// fallback), or `nil` when AX doesn't expose text attributes / the app is
    /// unresponsive (caller should try the clipboard fallback).
    private func captureViaAX() -> CaptureOutcome? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        // -25212 == kAXErrorCannotComplete: the source app is unresponsive to
        // AX. Synthesizing ⌘C at it is dangerous (latches the Command flag in
        // the window server), so bail without the clipboard fallback.
        if focusErr.rawValue == -25212 {
            axLog("source app unresponsive (-25212); skipping clipboard fallback")
            return .empty
        }

        guard focusErr == .success, let focused = focusedRef else {
            axLog("could not get focused element (err=\(focusErr.rawValue))")
            return nil
        }
        let element = focused as! AXUIElement
        focusedElement = element

        // Strategy 1: direct selected-text attribute.
        var textRef: CFTypeRef?
        let textStatus = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &textRef)
        if textStatus == .success {
            if let text = textRef as? String, !text.isEmpty {
                axLog("strategy 1 succeeded")
                return .text(text, source: .accessibility)
            }
            // AX is working; the user genuinely has no selection.
            return .empty
        }

        // Strategy 2: selected range → string-for-range parameterized attr.
        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        if rangeStatus == .success, let rangeValue = rangeRef {
            var stringRef: CFTypeRef?
            let stringStatus = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeValue,
                &stringRef)
            if stringStatus == .success {
                if let text = stringRef as? String, !text.isEmpty {
                    axLog("strategy 2 succeeded")
                    return .text(text, source: .accessibility)
                }
                return .empty
            }
        }

        // AX doesn't expose text attributes here — let the caller try ⌘C.
        return nil
    }

    private func selectedTextAttribute(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func selectedTextViaRange(of element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else { return nil }

        var stringRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &stringRef) == .success else { return nil }
        return stringRef as? String
    }

    // MARK: - Writing text back

    /// Outcome of a `replaceSelectedText(with:)` call.
    enum ReplaceOutcome {
        case replacedInPlace      // AX write, verified
        case pastedViaClipboard   // synthetic paste, confirmed by the destination
        case pastedUnverified     // pasted, but couldn't confirm — left on clipboard
        case readOnly             // field isn't editable — left on clipboard
        case focusChanged         // focus moved off the original field — left on clipboard
        case accessibilityRevoked
        case failed
    }

    /// Replaces the selection. Tries the AX text API first; if the host app
    /// rejects it (Notes etc.), pastes via the clipboard instead.
    ///
    /// Guards against the two classic system-wide-rewrite failures:
    ///  • the user clicked into a different field after triggering Modo
    ///    (focus-mismatch → don't write into the wrong place), and
    ///  • the write silently didn't take (verify AX writes; report low
    ///    confidence and leave the result on the clipboard otherwise).
    func replaceSelectedText(with newText: String) -> ReplaceOutcome {
        guard isTrusted else { return .accessibilityRevoked }

        let bundleID = sourceBundleID

        // Strategy 1: AX set value — only when the original capture came from AX.
        if lastCaptureSource == .accessibility, let element = focusedElement {
            // Focus-mismatch guard: if the focused element has changed since
            // capture, writing the AX value would land in the wrong field.
            if focusHasChanged(from: element) {
                axLog("focus changed since capture; falling back to clipboard keep")
                Observability.shared.logApply(tier: "ax", success: false, bundleID: bundleID)
                _ = pasteIntoClipboardOnly(newText)
                return .focusChanged
            }

            // Editability check → read-only Tier 3.
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(
                element, kAXSelectedTextAttribute as CFString, &settable)
            guard settable.boolValue else {
                axLog("selected text not settable; read-only Tier 3")
                Observability.shared.logApply(tier: "readonly", success: false, bundleID: bundleID)
                _ = pasteIntoClipboardOnly(newText)
                return .readOnly
            }

            let err = AXUIElementSetAttributeValue(
                element, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)
            if err == .success {
                // Verify: re-read the selected text and confirm it matches.
                let verified = verifyAXWrite(element: element, expected: newText)
                // Leave the cursor at the end of the inserted text rather than
                // re-selecting the whole insertion.
                let endRange = CFRange(location: (newText as NSString).length, length: 0)
                if let value = AXValueCreate(.cfRange, withUnsafePointer(to: endRange) { $0 }) {
                    AXUIElementSetAttributeValue(
                        element, kAXSelectedTextRangeAttribute as CFString, value)
                }
                if verified {
                    CapabilityCache.shared.recordApply(.accessibility, for: bundleID)
                    Observability.shared.logApply(tier: "ax", success: true, bundleID: bundleID)
                    return .replacedInPlace
                }
                // AX claimed success but the value didn't change — fall through
                // to the paste path rather than trusting an unverified write.
                axLog("AX write unverified; trying paste")
            }
        }

        // Strategy 2: paste via the clipboard (works wherever ⌘V works).
        switch pasteViaClipboard(newText) {
        case .confirmed:
            CapabilityCache.shared.recordApply(.paste, for: bundleID)
            Observability.shared.logApply(tier: "paste", success: true, bundleID: bundleID)
            return .pastedViaClipboard
        case .unconfirmed:
            CapabilityCache.shared.recordApply(.copyOnly, for: bundleID)
            Observability.shared.logApply(tier: "paste", success: false, bundleID: bundleID)
            return .pastedUnverified
        case .failed:
            Observability.shared.logApply(tier: "paste", success: false, bundleID: bundleID)
            return .failed
        }
    }

    /// True if the system-wide focused element no longer matches the element we
    /// captured the selection from (the user clicked elsewhere mid-session).
    private func focusHasChanged(from captured: AXUIElement) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var currentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &currentRef) == .success,
              let current = currentRef else {
            // Can't determine current focus — be conservative and treat as
            // unchanged so we don't needlessly downgrade to paste.
            return false
        }
        let currentElement = current as! AXUIElement
        return !CFEqual(currentElement, captured)
    }

    /// Re-reads the focused element's selected text to confirm an AX write
    /// actually landed. Some apps return `.success` from the set call but don't
    /// apply the change.
    private func verifyAXWrite(element: AXUIElement, expected: String) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &ref) == .success else {
            // Some fields clear the selection after a set; treat inability to
            // re-read as "can't verify" → caller keeps it low-confidence.
            return false
        }
        // After our write + cursor-collapse the selection is usually empty, so
        // an empty read is expected and not a failure signal. We only treat a
        // non-empty mismatch as a hard failure.
        if let now = ref as? String, !now.isEmpty {
            return now == expected
        }
        return true
    }

    /// Brings the app that owned the original selection back to the front.
    /// Call this whenever the popover is dismissed so the user's editor regains
    /// focus instead of leaving them in a "what just took my focus?" state.
    ///
    /// Self-clearing: drops `sourceApp` after use so a stale reference can
    /// never yank focus on a later code path (e.g. the workspace
    /// did-activate observer firing for a normal app-switch).
    func reactivateSourceApp() {
        defer { sourceApp = nil }
        if let sourceApp, !sourceApp.isActive {
            sourceApp.activate()
        }
    }

    // MARK: - Clipboard-based fallbacks

    /// Synthesizes ⌘C, waits for the front app to write to the pasteboard,
    /// reads the string, then restores the previous pasteboard contents.
    ///
    /// Distinguishes three results: `.text` (copy produced a string),
    /// `.nonText` (the pasteboard changed but holds no string — e.g. an image
    /// selection), and `.empty` (the copy timed out / nothing happened).
    private func selectionViaClipboardCopy() -> CaptureOutcome {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard(pasteboard)
        let beforeCount = pasteboard.changeCount

        sendCommandShortcut(keyC)

        // Poll for the front app to update the pasteboard. 500ms is generous
        // for sluggish apps without making the popover feel laggy.
        var changed = false
        var copied: String?
        waitForCondition(timeoutMS: 500) {
            if pasteboard.changeCount != beforeCount {
                copied = pasteboard.string(forType: .string)
                changed = true
                return true
            }
            return false
        }

        restorePasteboard(pasteboard, from: saved)

        if let text = copied, !text.isEmpty {
            return .text(text, source: .clipboard)
        }
        // The clipboard changed but yielded no text → the selection was an
        // image or other non-text content.
        if changed { return .nonText }
        return .empty
    }

    /// Confidence in a synthetic-paste apply.
    private enum PasteResult {
        case confirmed     // destination consumed the pasteboard — high confidence
        case unconfirmed   // ⌘V sent but no acknowledgement — low confidence
        case failed        // couldn't even attempt (no source app)
    }

    /// Puts `text` on the pasteboard and synthesizes ⌘V to paste it over the
    /// current selection.
    ///
    /// Clipboard hygiene: the user's prior clipboard (all items/types) is
    /// restored exactly whenever we actually deliver the ⌘V, so clipboard
    /// managers aren't clobbered. The ONE case we treat as low-confidence is
    /// when we couldn't bring the source app frontmost at all — then ⌘V would
    /// go nowhere useful, so we leave the improved text on the clipboard for
    /// the user to paste manually (the D2 "it's on your clipboard" path).
    ///
    /// Note: a successful paste does NOT move the pasteboard's changeCount
    /// (reading the pasteboard to paste doesn't increment it), so changeCount
    /// can't be used as a paste-success signal — we use it only as a settle
    /// wait before restoring.
    private func pasteViaClipboard(_ text: String) -> PasteResult {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let afterWrite = pasteboard.changeCount

        // Our panel may have taken focus; bring the source app back to the
        // front so ⌘V is delivered to it, then give it a moment to focus.
        guard let sourceApp else { return .failed }
        var becameActive = sourceApp.isActive
        if !becameActive {
            sourceApp.activate()
            becameActive = waitForCondition(timeoutMS: 400) { sourceApp.isActive }
        }
        guard becameActive else {
            // Couldn't refocus the source app — ⌘V can't be delivered. Leave
            // the improved text on the clipboard rather than restoring, so the
            // user can paste it themselves.
            axLog("source app didn't refocus; leaving result on clipboard")
            return .unconfirmed
        }

        sendCommandShortcut(keyV)

        // Settle: give the destination a moment to act on ⌘V before we restore
        // the user's clipboard.
        waitForCondition(timeoutMS: 300) { pasteboard.changeCount != afterWrite }

        // Restore the user's original clipboard exactly (every item/type).
        restorePasteboard(pasteboard, from: saved)
        return .confirmed
    }

    /// Leaves `text` on the clipboard without attempting a paste. Used by the
    /// read-only and focus-changed paths so the user can paste it where they
    /// want. The prior clipboard is intentionally not restored.
    @discardableResult
    private func pasteIntoClipboardOnly(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
    }

    /// Polls `condition` every 10ms up to `timeoutMS` and returns true if it
    /// ever became true. Used to wait on activation / pasteboard reads without
    /// hard-coded sleeps.
    @discardableResult
    private func waitForCondition(timeoutMS: Int, _ condition: () -> Bool) -> Bool {
        let steps = max(1, timeoutMS / 10)
        for _ in 0..<steps {
            if condition() { return true }
            usleep(10_000)
        }
        return false
    }

    /// Posts a Command-modified key down/up pair to the front application.
    /// The keystroke is bracketed by explicit "modifiers cleared" events so a
    /// dropped/queued ⌘ key cannot leave the window server believing Command
    /// is still held — that latched-modifier state was the root cause of the
    /// "Modo blocks events for other apps" bug.
    private func sendCommandShortcut(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap

        clearModifiers(source: source, tap: tap)

        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: tap)
        up?.post(tap: tap)

        clearModifiers(source: source, tap: tap)
    }

    /// Posts a `flagsChanged` event with no modifier flags set. The window
    /// server uses these events to track modifier state — sending an explicit
    /// "no modifiers" event reliably releases anything that got stuck.
    private func clearModifiers(source: CGEventSource?, tap: CGEventTapLocation) {
        guard let event = CGEvent(source: source) else { return }
        event.type = .flagsChanged
        event.flags = []
        event.post(tap: tap)
    }

    // MARK: - Pasteboard snapshot/restore

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.compactMap { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        } ?? []
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, from items: [NSPasteboardItem]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
