import SwiftUI

/// Sheet for routing each mode to a specific (provider, model) different from
/// the global default. Lets users save cost by sending grammar fixes through
/// a cheap/fast model while reserving stronger models for complex rewrites.
struct ModeRoutingView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var allModes: [Mode] = []
    @State private var overrides: [String: ModeOverride] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Per-Mode Model Routing").font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(allModes) { mode in
                        row(for: mode)
                        Divider()
                    }
                }
            }

            Divider()
            HStack {
                Text("Leave a row on \"Default\" to use the globally-selected provider and model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 480)
        .onAppear { reload() }
    }

    private func row(for mode: Mode) -> some View {
        let current = overrides[mode.id] ?? ModeOverride()
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: mode.systemSymbol)
                .frame(width: 24)
            Text(mode.title)
                .font(.callout)
                .frame(width: 110, alignment: .leading)
            Spacer()
            providerPicker(modeID: mode.id, current: current)
                .frame(width: 160)
            modelPicker(modeID: mode.id, current: current)
                .frame(width: 220)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func providerPicker(modeID: String, current: ModeOverride) -> some View {
        Picker("", selection: Binding(
            get: { current.providerRaw ?? "" },
            set: { newValue in
                var updated = current
                updated.providerRaw = newValue.isEmpty ? nil : newValue
                // Reset model when provider changes so the picker stays valid.
                updated.modelID = nil
                save(updated, for: modeID)
            }
        )) {
            Text("Default").tag("")
            ForEach(AIProvider.allCases) { provider in
                Text(provider.displayName).tag(provider.rawValue)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func modelPicker(modeID: String, current: ModeOverride) -> some View {
        if let providerRaw = current.providerRaw,
           let provider = AIProvider(rawValue: providerRaw) {
            if provider.usesCustomModelName {
                TextField("model-name", text: Binding(
                    get: { current.modelID ?? "" },
                    set: { newValue in
                        var updated = current
                        updated.modelID = newValue.isEmpty ? nil : newValue
                        save(updated, for: modeID)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                Picker("", selection: Binding(
                    get: { current.modelID ?? "" },
                    set: { newValue in
                        var updated = current
                        updated.modelID = newValue.isEmpty ? nil : newValue
                        save(updated, for: modeID)
                    }
                )) {
                    Text("Provider default").tag("")
                    ForEach(provider.models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            }
        } else {
            Text("—")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save(_ override: ModeOverride, for modeID: String) {
        overrides[modeID] = override
        ModeOverridesStore.shared.setOverride(override, for: modeID)
    }

    private func reload() {
        allModes = Mode.allBuiltIn + CustomModeStore.shared.load()
        overrides = ModeOverridesStore.shared.load()
    }
}
