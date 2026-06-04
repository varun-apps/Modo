import AppKit
import UniformTypeIdentifiers

/// Encodes/decodes the user-facing settings to a single JSON file so users can
/// migrate between Macs or back up their setup. **API keys are intentionally
/// excluded** — they live in the Keychain, and serializing them to a plain
/// file would defeat that protection.
enum SettingsExporter {

    struct Snapshot: Codable {
        var version: Int = 1
        var customModes: [Mode]
        var modeOverrides: [String: ModeOverride]
        var modeHotkeys: [String: HotkeyBinding]
        var globalHotkeyEnabled: Bool
        var globalHotkeyKeyCode: UInt32
        var globalHotkeyModifiers: UInt32
        var personalInstructions: String
        var toneDetectionEnabled: Bool
        var temperature: Double
        var lengthRawValue: String
        var providers: [String: ProviderSnapshot]

        struct ProviderSnapshot: Codable {
            var modelID: String
            var endpoint: String
        }
    }

    @MainActor
    static func snapshot() -> Snapshot {
        var providers: [String: Snapshot.ProviderSnapshot] = [:]
        for provider in AIProvider.allCases {
            providers[provider.rawValue] = .init(
                modelID: provider.currentModelID,
                endpoint: provider.currentEndpointString
            )
        }
        return Snapshot(
            customModes: CustomModeStore.shared.load(),
            modeOverrides: ModeOverridesStore.shared.load(),
            modeHotkeys: HotkeyService.shared.allModeBindings(),
            globalHotkeyEnabled: HotkeyService.shared.isEnabled,
            globalHotkeyKeyCode: HotkeyService.shared.currentKeyCode,
            globalHotkeyModifiers: HotkeyService.shared.currentModifiers,
            personalInstructions: PersonalInstructions.current,
            toneDetectionEnabled: WindowViewModel.isToneDetectionEnabled,
            temperature: GenerationSettings.temperature,
            lengthRawValue: GenerationSettings.length.rawValue,
            providers: providers
        )
    }

    @MainActor
    static func apply(_ snapshot: Snapshot) {
        CustomModeStore.shared.save(snapshot.customModes)
        for (modeID, override) in snapshot.modeOverrides {
            ModeOverridesStore.shared.setOverride(override, for: modeID)
        }
        for (modeID, binding) in snapshot.modeHotkeys {
            HotkeyService.shared.setModeBinding(binding, forModeID: modeID)
        }
        HotkeyService.shared.isEnabled = snapshot.globalHotkeyEnabled
        HotkeyService.shared.currentKeyCode = snapshot.globalHotkeyKeyCode
        HotkeyService.shared.currentModifiers = snapshot.globalHotkeyModifiers
        HotkeyService.shared.register()
        PersonalInstructions.current = snapshot.personalInstructions
        WindowViewModel.isToneDetectionEnabled = snapshot.toneDetectionEnabled
        GenerationSettings.temperature = snapshot.temperature
        if let length = GenerationSettings.Length(rawValue: snapshot.lengthRawValue) {
            GenerationSettings.length = length
        }
        for (raw, providerSnap) in snapshot.providers {
            guard let provider = AIProvider(rawValue: raw) else { continue }
            UserDefaults.standard.set(providerSnap.modelID, forKey: "selectedModel_\(provider.rawValue)")
            if provider.usesCustomEndpoint, !providerSnap.endpoint.isEmpty {
                UserDefaults.standard.set(providerSnap.endpoint, forKey: "endpoint_\(provider.rawValue)")
            }
        }
    }

    @MainActor
    static func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "modo-settings.json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot())
                try data.write(to: url)
            } catch {
                presentAlert("Could not export settings", error.localizedDescription)
            }
        }
    }

    @MainActor
    static func runImport(onComplete: @escaping () -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let snap = try JSONDecoder().decode(Snapshot.self, from: data)
                apply(snap)
                onComplete()
            } catch {
                presentAlert("Could not import settings", error.localizedDescription)
            }
        }
    }

    @MainActor
    private static func presentAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
