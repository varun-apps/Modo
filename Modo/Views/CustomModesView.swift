import SwiftUI

/// Sheet/window for managing user-defined custom modes.
/// Lists existing customs and lets the user add, edit, or delete them.
struct CustomModesView: View {
    @Binding var modes: [Mode]
    @State private var editing: Mode?
    @State private var isAdding = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Modes").font(.headline)
                Spacer()
                Button("Add Mode") { isAdding = true }
            }
            .padding(16)
            Divider()

            if modes.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(modes) { mode in
                        HStack {
                            Image(systemName: mode.systemSymbol)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title).font(.callout)
                                Text(mode.systemPrompt)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Edit") { editing = mode }
                                .buttonStyle(.borderless)
                            Button(role: .destructive) {
                                delete(mode)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
        .sheet(isPresented: $isAdding) {
            CustomModeEditor(mode: nil) { newMode in
                modes.append(newMode)
                save()
            }
        }
        .sheet(item: $editing) { mode in
            CustomModeEditor(mode: mode) { updated in
                if let idx = modes.firstIndex(where: { $0.id == mode.id }) {
                    modes[idx] = updated
                    save()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.rays")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No custom modes yet")
                .font(.callout)
            Text("Add a mode to create your own rewrite shortcut (e.g. \"Translate to German\").")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ mode: Mode) {
        modes.removeAll { $0.id == mode.id }
        save()
    }

    private func save() {
        CustomModeStore.shared.save(modes)
    }
}

/// Sheet for creating or editing a single custom mode.
struct CustomModeEditor: View {
    let mode: Mode?
    let onSave: (Mode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var symbol: String = "sparkles"
    @State private var prompt: String = ""
    @State private var isDirectPrompt: Bool = false
    @State private var targetLanguage: String = ""

    private static let languageChoices = [
        "", "English", "Spanish", "French", "German", "Italian", "Portuguese",
        "Dutch", "Russian", "Japanese", "Korean", "Chinese (Simplified)",
        "Chinese (Traditional)", "Hindi", "Arabic", "Turkish", "Polish", "Swedish"
    ]

    private static let symbolChoices = [
        "sparkles", "wand.and.stars", "globe", "text.bubble", "bubble.left",
        "pencil", "highlighter", "doc.text", "bolt", "lightbulb",
        "star", "flag", "tag", "leaf", "flame",
        "checkmark.seal", "arrow.right.circle", "translate"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == nil ? "New Custom Mode" : "Edit Custom Mode")
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()

            Form {
                Section {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Name")
                }

                Section {
                    Picker("Icon", selection: $symbol) {
                        ForEach(Self.symbolChoices, id: \.self) { name in
                            Label(name, systemImage: name).tag(name)
                        }
                    }
                } header: {
                    Text("Icon")
                }

                Section {
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("Instructions for the AI. The user's selected text will be passed as input. Tell the model to return only the rewritten result with no preamble.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Output Language", selection: $targetLanguage) {
                        ForEach(Self.languageChoices, id: \.self) { lang in
                            Text(lang.isEmpty ? "Preserve original" : lang).tag(lang)
                        }
                    }
                } footer: {
                    Text("Force the result to a specific language (useful for translation modes). Leave on \"Preserve original\" to keep the input's language.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Treat selection as a direct instruction (like Ask AI)", isOn: $isDirectPrompt)
                } footer: {
                    Text("When on, the selected text is sent as-is to the model. When off, it's wrapped in <text> tags and treated as content to be edited.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 16)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty ||
                              prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 540)
        .onAppear { populate() }
    }

    private func populate() {
        guard let mode else { return }
        title = mode.title
        symbol = mode.systemSymbol
        prompt = mode.systemPrompt
        isDirectPrompt = mode.isDirectPrompt
        targetLanguage = mode.targetLanguage ?? ""
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespaces)
        let id: String
        if let mode {
            id = String(mode.id.dropFirst("custom.".count))
        } else {
            id = UUID().uuidString
        }
        let language = targetLanguage.trimmingCharacters(in: .whitespaces)
        let newMode = Mode.custom(
            id: id,
            title: trimmedTitle,
            systemSymbol: symbol,
            systemPrompt: trimmedPrompt,
            isDirectPrompt: isDirectPrompt,
            targetLanguage: language.isEmpty ? nil : language
        )
        onSave(newMode)
        dismiss()
    }
}
