import SwiftUI

struct PreferencesView: View {
    @State private var selectedProvider: AIProvider = AIProvider.current
    @State private var apiKeys: [String: String] = [:]
    @State private var selectedModelIDs: [String: String] = [:]
    @State private var savedFlash = false
    @State private var hotkeyEnabled: Bool = HotkeyService.shared.isEnabled
    @State private var hotkeyKeyCode: UInt32 = HotkeyService.shared.currentKeyCode
    @State private var hotkeyModifiers: UInt32 = HotkeyService.shared.currentModifiers
    @State private var globalHotkeyConflict: Bool = HotkeyService.shared.failedBindings["global"] != nil
    @State private var openAtLogin: Bool = LaunchAtLoginService.isEnabled
    @ObservedObject private var updater = UpdaterService.shared
    @State private var customModes: [Mode] = CustomModeStore.shared.load()
    @State private var showingCustomModes = false
    @State private var showingModeHotkeys = false
    @State private var showingModeRouting = false
    @State private var personalInstructions: String = PersonalInstructions.current
    @State private var toneDetectionEnabled: Bool = WindowViewModel.isToneDetectionEnabled
    @State private var endpoints: [String: String] = [:]
    @State private var temperature: Double = GenerationSettings.temperature
    @State private var length: GenerationSettings.Length = GenerationSettings.length

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("AI Provider")
            }

            if selectedProvider.usesCustomEndpoint {
                Section {
                    TextField("https://…/v1/chat/completions", text: endpointBinding)
                        .textFieldStyle(.roundedBorder)
                    Text(selectedProvider == .ollama
                         ? "Default: http://localhost:11434/v1/chat/completions"
                         : "Any OpenAI-compatible chat completions URL.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Endpoint URL")
                }
            }

            Section {
                SecureField(selectedProvider.keyPlaceholder, text: keyBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!selectedProvider.requiresAPIKey && selectedProvider != .custom)
                Text(selectedProvider.keyHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("\(selectedProvider.displayName) API Key")
            }

            Section {
                if selectedProvider.usesCustomModelName {
                    TextField("model-name", text: modelBinding)
                        .textFieldStyle(.roundedBorder)
                    Text(selectedProvider == .ollama
                         ? "The local model name as it appears in `ollama list` (e.g. llama3.2, mistral, qwen2.5)."
                         : "The model identifier the endpoint expects.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: modelBinding) {
                        ForEach(selectedProvider.models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack {
                    Spacer()
                    Button("Per-Mode Routing…") { showingModeRouting = true }
                }
            } header: {
                Text("Model")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Creativity")
                        Spacer()
                        Text(String(format: "%.2f", temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $temperature, in: 0...1, step: 0.05) {
                        Text("Creativity")
                    } minimumValueLabel: {
                        Text("Strict").font(.caption2).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Creative").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Picker("Length", selection: $length) {
                    ForEach(GenerationSettings.Length.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Text("Lower creativity gives more predictable edits; higher creativity allows more rewriting. Length caps the model's output (short ≈ 512 tokens, long ≈ 4096).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Generation")
            }

            Section {
                Toggle("Detect tone of selection before rewriting", isOn: $toneDetectionEnabled)
                Text("Makes a small extra API call to describe how your text reads (e.g. \"This sounds blunt.\"). Disable to skip the call and save tokens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Tone Detection")
            }

            Section {
                TextEditor(text: $personalInstructions)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                Text("Applied to every mode. Examples: \"I'm British, keep -our spellings.\" \"Never use em-dashes.\" \"Always capitalize Acme product names exactly as written.\"")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Personal Instructions")
            }

            Section {
                HStack {
                    Text("\(customModes.count) custom mode\(customModes.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Manage Custom Modes…") { showingCustomModes = true }
                }
                Text("Create your own rewrite shortcuts (e.g. \"Translate to German\", \"Reply politely declining\").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Custom Modes")
            }

            Section {
                Toggle("Enable global hotkey", isOn: $hotkeyEnabled)
                HStack {
                    Text("Shortcut")
                    Spacer()
                    HotkeyRecorderField(keyCode: $hotkeyKeyCode, modifiers: $hotkeyModifiers)
                        .frame(width: 160)
                }
                .disabled(!hotkeyEnabled)
                Text("Press this key combination from any app to open Modo with the current selection. Click the field above and press the desired keys to change it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if globalHotkeyConflict {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("This shortcut is already in use by macOS or another app — pick a different combination.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                HStack {
                    Spacer()
                    Button("Configure Per-Mode Hotkeys…") { showingModeHotkeys = true }
                }
            } header: {
                Text("Global Hotkey")
            }

            if LaunchAtLoginService.isAvailable {
                Section {
                    Toggle("Launch Modo at login", isOn: $openAtLogin)
                        .onChange(of: openAtLogin) { _, newValue in
                            if !LaunchAtLoginService.setEnabled(newValue) {
                                // Roll back the toggle if macOS refused.
                                openAtLogin = LaunchAtLoginService.isEnabled
                            }
                        }
                } header: {
                    Text("Startup")
                }
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                HStack {
                    Button("Check Now…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                    Spacer()
                }
                Text("Modo uses Sparkle to deliver signed updates from GitHub Releases. You can disable automatic checks any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Updates")
            }

            Section {
                HStack {
                    Button("Export Settings…") { SettingsExporter.runExport() }
                    Button("Import Settings…") {
                        SettingsExporter.runImport { loadAll() }
                    }
                    Spacer()
                }
                Text("Exports your custom modes, hotkeys, generation controls, and per-mode routing as a JSON file. API keys are kept in the Keychain and not included.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Backup")
            }

            Section {
                HStack {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                    if savedFlash {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    }
                    Spacer()
                    Button {
                        NotificationCenter.default.post(name: .openModoHelp, object: nil)
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .onAppear { loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: HotkeyService.conflictsDidChangeNotification)) { _ in
            globalHotkeyConflict = HotkeyService.shared.failedBindings["global"] != nil
        }
        .sheet(isPresented: $showingCustomModes) {
            CustomModesView(modes: $customModes)
        }
        .sheet(isPresented: $showingModeHotkeys) {
            ModeHotkeysView()
        }
        .sheet(isPresented: $showingModeRouting) {
            ModeRoutingView()
        }
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { apiKeys[selectedProvider.keychainAccount] ?? "" },
            set: { apiKeys[selectedProvider.keychainAccount] = $0 }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { selectedModelIDs[selectedProvider.rawValue] ?? selectedProvider.defaultModel.id },
            set: { selectedModelIDs[selectedProvider.rawValue] = $0 }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { endpoints[selectedProvider.rawValue] ?? selectedProvider.defaultEndpointString },
            set: { endpoints[selectedProvider.rawValue] = $0 }
        )
    }

    private func loadAll() {
        for provider in AIProvider.allCases {
            apiKeys[provider.keychainAccount] = KeychainService.loadKey(for: provider.keychainAccount) ?? ""
            selectedModelIDs[provider.rawValue] = provider.currentModelID
            endpoints[provider.rawValue] = provider.currentEndpointString
        }
    }

    private func save() {
        AIProvider.current = selectedProvider
        for provider in AIProvider.allCases {
            KeychainService.saveKey(apiKeys[provider.keychainAccount] ?? "", for: provider.keychainAccount)
            if let modelID = selectedModelIDs[provider.rawValue] {
                UserDefaults.standard.set(modelID, forKey: "selectedModel_\(provider.rawValue)")
            }
            if provider.usesCustomEndpoint, let endpoint = endpoints[provider.rawValue] {
                UserDefaults.standard.set(endpoint, forKey: "endpoint_\(provider.rawValue)")
            }
        }
        HotkeyService.shared.updateHotkey(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
        HotkeyService.shared.setEnabled(hotkeyEnabled)
        PersonalInstructions.current = personalInstructions
        WindowViewModel.isToneDetectionEnabled = toneDetectionEnabled
        GenerationSettings.temperature = temperature
        GenerationSettings.length = length
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
    }
}
