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

    /// Reads the current selection, trying the cheapest, least intrusive method
    /// first and falling back to a clipboard copy for apps that don't expose
    /// the AX text attributes. Returns nil only when nothing is selected.
    func readSelectedText() -> String? {
        axLog("readSelectedText called, isTrusted=\(isTrusted)")
        focusedElement = nil
        guard isTrusted else {
            axLog("aborting — accessibility not trusted")
            return nil
        }

        sourceApp = NSWorkspace.shared.frontmostApplication
        axLog("frontmostApp: \(sourceApp?.localizedName ?? "nil")")

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        // -25212 == kAXErrorCannotComplete. This typically means the source
        // app is unresponsive to AX queries. Synthesizing ⌘C at an
        // unresponsive app is dangerous: the events queue in the window
        // server with the Command-modifier flag latched, and the next
        // user click/keystroke gets interpreted as Command-click / ⌘key.
        let sourceUnresponsive = (focusErr.rawValue == -25212)

        // Track whether AX *worked* against the focused element — even if it
        // reported an empty selection. When AX-aware apps (Xcode, native text
        // views) report "no selection", we must NOT fall through to the ⌘C
        // fallback: poking a happy app with synthesized modifier-stamped
        // keystrokes is what was latching the Command flag in the window
        // server and blocking subsequent input.
        var axReportedDefinitiveNoSelection = false

        if focusErr == .success, let focused = focusedRef {
            let element = focused as! AXUIElement
            focusedElement = element

            // Strategy 1: direct selected-text attribute.
            var textRef: CFTypeRef?
            let textStatus = AXUIElementCopyAttributeValue(
                element, kAXSelectedTextAttribute as CFString, &textRef)
            if textStatus == .success {
                if let text = textRef as? String, !text.isEmpty {
                    axLog("strategy 1 succeeded")
                    return text
                }
                // AX is working; the user genuinely has no selection.
                axReportedDefinitiveNoSelection = true
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
                        return text
                    }
                    axReportedDefinitiveNoSelection = true
                }
            }
        } else {
            axLog("could not get focused element (err=\(focusErr.rawValue))")
        }

        // Skip the clipboard fallback when the source app is unresponsive —
        // synthesized keystrokes against an unresponsive app are exactly what
        // produced the "Modo blocks events for other apps" bug.
        guard !sourceUnresponsive else {
            axLog("source app unresponsive (-25212); skipping clipboard fallback")
            return nil
        }

        // If AX explicitly told us there is no selection, trust it. The ⌘C
        // fallback is only for apps where AX doesn't expose text attributes
        // at all (Notes, Mail, Electron editors).
        guard !axReportedDefinitiveNoSelection else {
            axLog("AX reports no selection; skipping clipboard fallback")
            return nil
        }

        // Strategy 3: clipboard fallback (Notes, Mail, Word, web/Electron editors).
        if let text = selectionViaClipboardCopy(), !text.isEmpty {
            axLog("strategy 3 (clipboard) succeeded")
            return text
        }
        axLog("all strategies failed — returning nil")
        return nil
    }

    // MARK: - Lightweight selection probe (no keystroke fallback)

    /// Quick, side-effect-free read of the current AX selection: the text and
    /// its on-screen bounding rect, in **screen (bottom-left origin)** AppKit
    /// coordinates. Used by `SelectionMonitor` to decide whether to show the
    /// floating overlay near a user's selection.
    ///
    /// Returns `nil` when there is no selection, when the source app is
    /// unresponsive, when the focused element refuses AX text attributes, or
    /// when the bounding rect can't be retrieved — all of those mean "don't
    /// show the overlay". This function NEVER synthesizes keystrokes.
    ///
    /// Safe to call from any thread. Internally caps each AX call at 250 ms
    /// so a slow target app can't stall the caller — without this, repeated
    /// sync AX queries against an unresponsive app would back up the
    /// WindowServer's delivery queue and delay focus changes in unrelated
    /// apps.
    nonisolated static func peekSelectionWithBounds() -> (text: String, bounds: CGRect)? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        // Per-element timeout. AX defaults to ~6 seconds, which is unacceptable
        // for a 1Hz background poller.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)

        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        // Skip secure text fields — never reveal a password selection.
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String,
           subrole == (kAXSecureTextFieldSubrole as String) {
            return nil
        }

        // Need both the selected range (for bounds lookup) and the selected text.
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else { return nil }

        var lengthRange = CFRange(location: 0, length: 0)
        AXValueGetValue(rangeValue as! AXValue, .cfRange, &lengthRange)
        guard lengthRange.length > 0 else { return nil }

        var stringRef: CFTypeRef?
        let stringStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &stringRef)
        guard stringStatus == .success,
              let text = stringRef as? String,
              !text.isEmpty else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef) == .success,
              let boundsValue = boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect),
              rect.size.width > 0, rect.size.height > 0 else { return nil }

        // AX returns top-left-origin coordinates. Convert to AppKit's bottom-
        // left-origin so the rect can be passed directly to NSWindow.setFrame.
        if let primaryScreen = NSScreen.screens.first {
            let screenHeight = primaryScreen.frame.maxY
            rect.origin.y = screenHeight - rect.origin.y - rect.size.height
        }

        return (text, rect)
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
        case replacedInPlace
        case pastedViaClipboard
        case accessibilityRevoked
        case failed
    }

    /// Replaces the selection. Tries the AX text API first; if the host app
    /// rejects it (Notes etc.), pastes via the clipboard instead.
    func replaceSelectedText(with newText: String) -> ReplaceOutcome {
        guard isTrusted else { return .accessibilityRevoked }

        // Strategy 1: AX set value on the captured focused element.
        if let element = focusedElement {
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(
                element, kAXSelectedTextAttribute as CFString, &settable)
            if settable.boolValue {
                let err = AXUIElementSetAttributeValue(
                    element, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)
                if err == .success {
                    // Leave the cursor at the end of the inserted text rather
                    // than re-selecting the whole insertion.
                    let endRange = CFRange(location: (newText as NSString).length, length: 0)
                    if let value = AXValueCreate(.cfRange, withUnsafePointer(to: endRange) { $0 }) {
                        AXUIElementSetAttributeValue(
                            element, kAXSelectedTextRangeAttribute as CFString, value)
                    }
                    return .replacedInPlace
                }
            }
        }

        // Strategy 2: paste via the clipboard (works wherever ⌘V works).
        return pasteViaClipboard(newText) ? .pastedViaClipboard : .failed
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
    private func selectionViaClipboardCopy() -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard(pasteboard)
        let beforeCount = pasteboard.changeCount

        sendCommandShortcut(keyC)

        // Poll for the front app to update the pasteboard. 500ms is generous
        // for sluggish apps without making the popover feel laggy.
        var copied: String?
        waitForCondition(timeoutMS: 500) {
            if pasteboard.changeCount != beforeCount {
                copied = pasteboard.string(forType: .string)
                return true
            }
            return false
        }

        restorePasteboard(pasteboard, from: saved)
        return copied
    }

    /// Puts `text` on the pasteboard and synthesizes ⌘V to paste it over the
    /// current selection, then restores the previous pasteboard contents.
    /// Waits for the destination app to acknowledge the paste by observing the
    /// pasteboard's changeCount, rather than relying on a fixed delay.
    private func pasteViaClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let afterWrite = pasteboard.changeCount

        // Our panel may have taken focus; bring the source app back to the
        // front so ⌘V is delivered to it, then give it a moment to focus.
        if let sourceApp, !sourceApp.isActive {
            sourceApp.activate()
            waitForCondition(timeoutMS: 400) { sourceApp.isActive }
        }

        sendCommandShortcut(keyV)

        // Wait for the destination app to consume the pasteboard (it may read
        // and write to it) or for a soft timeout. This is far more reliable
        // than a fixed sleep, especially on slower Macs.
        waitForCondition(timeoutMS: 500) { pasteboard.changeCount != afterWrite }

        restorePasteboard(pasteboard, from: saved)
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
