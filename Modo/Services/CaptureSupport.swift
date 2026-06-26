import AppKit
import Carbon

/// Where a captured selection came from. Threaded through capture → apply so
/// the apply chain can pick the matching write strategy and the capability
/// cache can remember what worked per app.
enum CaptureSource: String, Codable {
    case accessibility   // read via the AX text attributes
    case clipboard       // read via a synthetic ⌘C fallback
}

/// Outcome of a selection capture attempt. Lets the UI distinguish "nothing
/// selected" from genuinely unsupported contexts (password fields, VMs, image
/// selections) so it can show an honest message instead of a generic error.
enum CaptureOutcome {
    case text(String, source: CaptureSource)
    case empty            // AX/clipboard worked but nothing is selected
    case secureField      // a secure-input context (password field) is active
    case unsupportedApp   // VM host / remote-desktop client — can't read reliably
    case nonText          // the selection produced non-text (e.g. an image)
    case disabledForApp   // the user turned Modo off for the frontmost app
}

/// Known bundle identifiers where system-wide text capture is unreliable or
/// impossible: virtual-machine hosts and remote-desktop clients render their
/// guest content as an opaque image, so neither AX nor synthetic copy can read
/// the "selected" text. We detect these early and show a graceful message
/// rather than firing doomed AX queries / stray ⌘C keystrokes at them.
enum UnsupportedApps {
    static let vmAndRemoteBundleIDs: Set<String> = [
        // Virtual machines
        "com.parallels.desktop.console",
        "com.parallels.vm",
        "com.vmware.fusion",
        "org.virtualbox.app.VirtualBoxVM",
        "com.utmapp.UTM",
        // Remote desktop / screen sharing
        "com.microsoft.rdc.macos",
        "com.citrix.receiver.icaviewer.mac",
        "com.citrix.XenAppViewer",
        "com.apple.ScreenSharing",
        "com.apple.RemoteDesktop",
        "com.teamviewer.TeamViewer",
        "com.philandro.anydesk",
        "com.p5sys.jump.mac.viewer",
        "com.nomachine.nxplayer",
        "com.realvnc.vncviewer",
    ]

    static func isVMOrRemote(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return vmAndRemoteBundleIDs.contains(bundleID)
    }
}

/// Secure-input detection. When a password field (or a terminal in secure
/// keyboard-entry mode) is focused anywhere on the system, macOS sets the
/// secure-input flag. Reading or synthesizing keystrokes around such a field is
/// both disallowed and a privacy hazard, so we bail out before touching AX or
/// the pasteboard.
enum SecureInput {
    static var isActive: Bool {
        IsSecureEventInputEnabled()
    }
}

/// Normalizes and length-limits text before it is sent to an AI provider.
/// Keeps the capture path and the engine call consistent and protects latency,
/// cost, and the diff renderer from pathologically large inputs.
enum TextSanitizer {
    /// Hard ceiling on characters sent to the engine (~5k tokens of English).
    static let maxInputCharacters = 20_000

    /// Collapse platform line endings to `\n` and trim surrounding whitespace.
    /// Content is otherwise preserved verbatim.
    static func normalize(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return unified.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Enforce the character ceiling. Returns the (possibly truncated) text and
    /// whether truncation occurred so the caller can surface a notice.
    static func enforceLimit(_ text: String) -> (text: String, truncated: Bool) {
        guard text.count > maxInputCharacters else { return (text, false) }
        let clipped = String(text.prefix(maxInputCharacters))
        return (clipped, true)
    }
}
