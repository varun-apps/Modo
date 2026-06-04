import SwiftUI

/// First-run wizard: welcome → pick provider & API key → grant Accessibility →
/// confirm hotkey. Sets a UserDefaults flag when finished so it doesn't show
/// again on subsequent launches.
struct OnboardingView: View {
    static let completedKey = "hasCompletedOnboarding_v1"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    var onFinish: () -> Void = {}

    @State private var step: Int = 0
    @State private var selectedProvider: AIProvider = .groq
    @State private var apiKey: String = ""
    @State private var hasAccessibility: Bool = AXIsProcessTrusted()
    @State private var pollTimer: Timer?

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch step {
                case 0: welcomeStep
                case 1: apiKeyStep
                case 2: accessibilityStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)

            Divider()
            footer
        }
        .frame(width: 520, height: 480)
        .onAppear(perform: startPolling)
        .onDisappear { pollTimer?.invalidate() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkle")
            Text("Welcome to Modo").font(.headline)
            Spacer()
            Text("Step \(step + 1) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rewrite any text with AI, anywhere on your Mac")
                .font(.title3.weight(.semibold))
            Text("Select text in any app, click the M in the menu bar (or use a hotkey), pick a mode, and Modo rewrites it for you. Replace in place or copy.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Label("Bring your own API key — no subscription.", systemImage: "key.fill")
                Label("Keys live in the macOS Keychain. Nothing leaves your Mac except your text → chosen provider.", systemImage: "lock.shield")
                Label("Custom modes, per-mode hotkeys, local Ollama support, and more.", systemImage: "wand.and.stars")
            }
            .font(.callout)
            Spacer()
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a provider and paste your API key")
                .font(.title3.weight(.semibold))

            Picker("Provider", selection: $selectedProvider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedProvider) { _, newValue in
                apiKey = KeychainService.loadKey(for: newValue.keychainAccount) ?? ""
            }

            SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .disabled(!selectedProvider.requiresAPIKey)

            Text(selectedProvider.keyHelpText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !selectedProvider.requiresAPIKey {
                Text("Ollama runs locally and doesn't need a key. Make sure it's running before you use Modo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("You can change provider, model, and key any time in Preferences (right-click the menu bar icon).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            apiKey = KeychainService.loadKey(for: selectedProvider.keychainAccount) ?? ""
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant Accessibility access")
                .font(.title3.weight(.semibold))
            Text("To read the text you select and to write the improved version back, macOS asks for Accessibility access. It's the one permission Modo needs to work.")
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: hasAccessibility ? "checkmark.seal.fill" : "exclamationmark.shield")
                    .foregroundStyle(hasAccessibility ? .green : .orange)
                Text(hasAccessibility ? "Accessibility is enabled" : "Accessibility is not yet granted")
                    .font(.callout.weight(.medium))
            }

            Button {
                AccessibilityService.shared.openAccessibilitySettings()
            } label: {
                Label("Open System Settings → Accessibility", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)

            Text("Find Modo in the list and turn its switch on. This window updates automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You're ready to go")
                .font(.title3.weight(.semibold))
            Text("Select text in any app, then press ⌥ Space (or click the M in the menu bar) to open Modo.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("Right-click the menu bar icon to open Preferences, History, or Quit.", systemImage: "info.circle")
                Label("Set per-mode hotkeys to run a specific mode in one keystroke.", systemImage: "command")
                Label("Add your own custom modes (Translate, Reply, etc.) from Preferences.", systemImage: "wand.and.rays")
            }
            .font(.callout)

            HStack {
                Button {
                    NotificationCenter.default.post(name: .openModoHelp, object: nil)
                } label: {
                    Label("Open Help", systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
            } else {
                Button("Skip") { finish() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step < totalSteps - 1 {
                Button(nextTitle) { advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Finish") { finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private var nextTitle: String {
        switch step {
        case 1: return "Save & Continue"
        default: return "Continue"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1:
            return !selectedProvider.requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    private func advance() {
        if step == 1 {
            AIProvider.current = selectedProvider
            KeychainService.saveKey(apiKey, for: selectedProvider.keychainAccount)
        }
        step += 1
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinish()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let trusted = AXIsProcessTrusted()
            if trusted != hasAccessibility {
                hasAccessibility = trusted
            }
        }
    }
}
