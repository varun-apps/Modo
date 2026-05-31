import AppKit
import ApplicationServices
import CoreGraphics

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

    /// On first launch, if not trusted, show a one-time alert pointing the
    /// user to System Settings. Also triggers the system prompt.
    func promptForPermissionIfNeeded() {
        guard !isTrusted else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        let alert = NSAlert()
        alert.messageText = "Enable Accessibility for Modo"
        alert.informativeText = """
        Modo needs Accessibility access to read the text you select in \
        other apps and to replace it with improved text.

        Open System Settings → Privacy & Security → Accessibility and turn on \
        Modo.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
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
        print("[WB-AX] readSelectedText called")
        print("[WB-AX] isTrusted: \(isTrusted)")
        focusedElement = nil
        guard isTrusted else {
            print("[WB-AX] aborting — accessibility not trusted")
            return nil
        }

        sourceApp = NSWorkspace.shared.frontmostApplication
        print("[WB-AX] frontmostApp: \(sourceApp?.localizedName ?? "nil") (pid \(sourceApp?.processIdentifier ?? -1))")

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        print("[WB-AX] focused element error: \(focusErr.rawValue)")
        if focusErr == .success, let focused = focusedRef {
            let element = focused as! AXUIElement
            focusedElement = element

            // Strategy 1: direct selected-text attribute.
            if let text = selectedTextAttribute(of: element), !text.isEmpty {
                print("[WB-AX] strategy 1 succeeded: '\(text.prefix(60))'")
                return text
            }
            print("[WB-AX] strategy 1 failed")

            // Strategy 2: selected range → string-for-range parameterized attr.
            if let text = selectedTextViaRange(of: element), !text.isEmpty {
                print("[WB-AX] strategy 2 succeeded: '\(text.prefix(60))'")
                return text
            }
            print("[WB-AX] strategy 2 failed")
        } else {
            print("[WB-AX] could not get focused element")
        }

        // Strategy 3: clipboard fallback (Notes, Mail, Word, web/Electron editors).
        print("[WB-AX] trying strategy 3 — clipboard copy")
        if let text = selectionViaClipboardCopy(), !text.isEmpty {
            print("[WB-AX] strategy 3 succeeded: '\(text.prefix(60))'")
            return text
        }
        print("[WB-AX] all strategies failed — returning nil")
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

    /// Replaces the selection. Tries the AX text API first; if the host app
    /// rejects it (Notes etc.), pastes via the clipboard instead. Returns true
    /// when the original text was replaced in place, false when we could only
    /// leave the result on the clipboard.
    @discardableResult
    func replaceSelectedText(with newText: String) -> Bool {
        guard isTrusted else { return false }

        // Strategy 1: AX set value on the captured focused element.
        if let element = focusedElement {
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(
                element, kAXSelectedTextAttribute as CFString, &settable)
            if settable.boolValue {
                let err = AXUIElementSetAttributeValue(
                    element, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)
                if err == .success { return true }
            }
        }

        // Strategy 2: paste via the clipboard (works wherever ⌘V works).
        return pasteViaClipboard(newText)
    }

    // MARK: - Clipboard-based fallbacks

    /// Synthesizes ⌘C, waits for the front app to write to the pasteboard,
    /// reads the string, then restores the previous pasteboard contents.
    private func selectionViaClipboardCopy() -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard(pasteboard)
        let beforeCount = pasteboard.changeCount

        sendCommandShortcut(keyC)

        // Poll for the front app to update the pasteboard (up to ~300ms).
        var copied: String?
        for _ in 0..<30 {
            if pasteboard.changeCount != beforeCount {
                copied = pasteboard.string(forType: .string)
                break
            }
            usleep(10_000) // 10ms
        }

        restorePasteboard(pasteboard, from: saved)
        return copied
    }

    /// Puts `text` on the pasteboard and synthesizes ⌘V to paste it over the
    /// current selection, then restores the previous pasteboard contents.
    private func pasteViaClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Our panel may have taken focus; bring the source app back to the
        // front so ⌘V is delivered to it, then give it a moment to focus.
        if let sourceApp, !sourceApp.isActive {
            sourceApp.activate()
            usleep(80_000) // 80ms for activation to settle
        }

        sendCommandShortcut(keyV)

        // Give the front app a moment to read the pasteboard before we restore.
        usleep(120_000) // 120ms
        restorePasteboard(pasteboard, from: saved)
        return true
    }

    /// Posts a Command-modified key down/up pair to the front application.
    private func sendCommandShortcut(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
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
