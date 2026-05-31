import SwiftUI

struct PreferencesView: View {
    @State private var selectedProvider: AIProvider = AIProvider.current
    @State private var apiKeys: [String: String] = [:]
    @State private var selectedModelIDs: [String: String] = [:]
    @State private var savedFlash = false

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

            Section {
                SecureField(selectedProvider.keyPlaceholder, text: keyBinding)
                    .textFieldStyle(.roundedBorder)
                Text(selectedProvider.keyHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("\(selectedProvider.displayName) API Key")
            }

            Section {
                Picker("Model", selection: modelBinding) {
                    ForEach(selectedProvider.models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Model")
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
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .onAppear { loadAll() }
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

    private func loadAll() {
        for provider in AIProvider.allCases {
            apiKeys[provider.keychainAccount] = KeychainService.loadKey(for: provider.keychainAccount) ?? ""
            selectedModelIDs[provider.rawValue] = provider.currentModelID
        }
    }

    private func save() {
        AIProvider.current = selectedProvider
        for provider in AIProvider.allCases {
            KeychainService.saveKey(apiKeys[provider.keychainAccount] ?? "", for: provider.keychainAccount)
            if let modelID = selectedModelIDs[provider.rawValue] {
                UserDefaults.standard.set(modelID, forKey: "selectedModel_\(provider.rawValue)")
            }
        }
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
    }
}
