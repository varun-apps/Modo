import AppKit
import Carbon

/// A single hotkey binding: keyCode + Carbon modifiers.
struct HotkeyBinding: Codable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
}

/// Registers system-wide hotkeys using Carbon's RegisterEventHotKey API.
/// Supports one global hotkey (opens the popover) and any number of per-mode
/// hotkeys (open the popover and immediately run a specific mode).
final class HotkeyService {
    static let shared = HotkeyService()

    private enum HotkeyKind {
        case global
        case mode(String)
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var kinds: [UInt32: HotkeyKind] = [:]
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    private let keyCodeKey = "globalHotkey_keyCode"
    private let modifiersKey = "globalHotkey_modifiers"
    private let enabledKey = "globalHotkey_enabled"
    private let modeBindingsKey = "modeHotkeys_v1"

    // Default: Option + Space
    static let defaultKeyCode: UInt32 = UInt32(kVK_Space)
    static let defaultModifiers: UInt32 = UInt32(optionKey)

    var globalCallback: (() -> Void)?
    var modeCallback: ((String) -> Void)?

    /// Tracks which configured bindings failed to register (typically because
    /// the OS or another app already owns the combination). Keyed by a stable
    /// label: "global" or the mode id.
    private(set) var failedBindings: [String: HotkeyBinding] = [:]

    /// Posted whenever `register()` runs and the list of conflicts changes.
    static let conflictsDidChangeNotification = Notification.Name("Modo.HotkeyConflictsChanged")

    private init() {}

    // MARK: - Global hotkey settings

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var currentKeyCode: UInt32 {
        get { UInt32(UserDefaults.standard.object(forKey: keyCodeKey) as? Int ?? Int(Self.defaultKeyCode)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: keyCodeKey) }
    }

    var currentModifiers: UInt32 {
        get { UInt32(UserDefaults.standard.object(forKey: modifiersKey) as? Int ?? Int(Self.defaultModifiers)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: modifiersKey) }
    }

    // MARK: - Per-mode hotkey settings

    /// Returns the stored binding for a given mode, if any.
    func binding(forModeID modeID: String) -> HotkeyBinding? {
        loadModeBindings()[modeID]
    }

    /// All stored per-mode bindings.
    func allModeBindings() -> [String: HotkeyBinding] {
        loadModeBindings()
    }

    func setModeBinding(_ binding: HotkeyBinding?, forModeID modeID: String) {
        var bindings = loadModeBindings()
        if let binding {
            bindings[modeID] = binding
        } else {
            bindings.removeValue(forKey: modeID)
        }
        saveModeBindings(bindings)
    }

    private func loadModeBindings() -> [String: HotkeyBinding] {
        guard let data = UserDefaults.standard.data(forKey: modeBindingsKey),
              let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data)
        else { return [:] }
        // Drop any binding without modifiers — those would intercept bare
        // keys system-wide (e.g. plain Return), which is never what a user
        // wants and how Modo could end up "stealing" Enter from Finder.
        let sanitized = decoded.filter { $0.value.modifiers != 0 }
        if sanitized.count != decoded.count {
            saveModeBindings(sanitized)
        }
        return sanitized
    }

    private func saveModeBindings(_ bindings: [String: HotkeyBinding]) {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: modeBindingsKey)
        }
    }

    // MARK: - Convenience callbacks

    func setCallback(_ callback: @escaping () -> Void) {
        self.globalCallback = callback
    }

    // MARK: - Registration

    /// Registers the global hotkey (if enabled) plus every per-mode binding.
    /// Records any combinations that failed to register so the UI can warn
    /// the user about conflicts (Spotlight, an already-running app, etc.).
    func register() {
        unregisterAll()
        installEventHandlerIfNeeded()
        var failed: [String: HotkeyBinding] = [:]

        // If the persisted global binding lost its modifiers somehow, reset
        // it to the safe default rather than registering a key-only hotkey.
        if currentModifiers == 0 {
            currentKeyCode = Self.defaultKeyCode
            currentModifiers = Self.defaultModifiers
        }

        if isEnabled {
            let ok = registerOne(keyCode: currentKeyCode, modifiers: currentModifiers, kind: .global)
            if !ok {
                failed["global"] = HotkeyBinding(keyCode: currentKeyCode, modifiers: currentModifiers)
            }
        }

        for (modeID, binding) in loadModeBindings() {
            let ok = registerOne(keyCode: binding.keyCode, modifiers: binding.modifiers, kind: .mode(modeID))
            if !ok {
                failed[modeID] = binding
            }
        }

        let changed = failed != failedBindings
        failedBindings = failed
        if changed {
            NotificationCenter.default.post(name: Self.conflictsDidChangeNotification, object: nil)
        }
    }

    func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        kinds.removeAll()
    }

    @discardableResult
    private func registerOne(keyCode: UInt32, modifiers: UInt32, kind: HotkeyKind) -> Bool {
        // SAFETY: never register a modifier-less hotkey. Carbon will happily
        // grab a bare key like Return, Space, or a letter system-wide, which
        // would steal those keystrokes from every other app. The recorder
        // fields already reject this, but corrupted UserDefaults or imported
        // settings could still produce one — guard here as the last line.
        guard modifiers != 0 else { return false }

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4F444F), id: id) // 'MODO'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        kinds[id] = kind
        return true
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(),
                            { (_, event, userData) -> OSStatus in
                                guard let userData, let event else { return noErr }
                                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                                var hotKeyID = EventHotKeyID()
                                let err = GetEventParameter(event,
                                                            EventParamName(kEventParamDirectObject),
                                                            EventParamType(typeEventHotKeyID),
                                                            nil,
                                                            MemoryLayout<EventHotKeyID>.size,
                                                            nil,
                                                            &hotKeyID)
                                guard err == noErr else { return noErr }
                                let id = hotKeyID.id
                                DispatchQueue.main.async {
                                    service.dispatchHotkey(id: id)
                                }
                                return noErr
                            },
                            1,
                            &eventSpec,
                            selfPointer,
                            &eventHandlerRef)
    }

    private func dispatchHotkey(id: UInt32) {
        guard let kind = kinds[id] else { return }
        switch kind {
        case .global:
            globalCallback?()
        case .mode(let modeID):
            modeCallback?(modeID)
        }
    }

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        register()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        register()
    }

    // MARK: - Display helpers

    /// Returns a human-readable string like "⌥Space" or "⌃⌘M".
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let char = characterFromKeyCode(keyCode) {
                return char.uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    private static func characterFromKeyCode(_ keyCode: UInt32) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        let maxStringLength = 4
        var actualStringLength = 0
        var unicodeString = [UniChar](repeating: 0, count: maxStringLength)

        let status = UCKeyTranslate(keyLayout,
                                    UInt16(keyCode),
                                    UInt16(kUCKeyActionDisplay),
                                    0,
                                    UInt32(LMGetKbdType()),
                                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeyState,
                                    maxStringLength,
                                    &actualStringLength,
                                    &unicodeString)

        guard status == noErr, actualStringLength > 0 else { return nil }
        return String(utf16CodeUnits: unicodeString, count: actualStringLength)
    }

    /// Converts NSEvent modifier flags to Carbon modifier flags.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
