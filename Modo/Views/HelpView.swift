import SwiftUI

/// In-app Help window. Sidebar lists topics; the right pane shows the
/// selected topic's content. Pure SwiftUI — no WebKit, no external network.
struct HelpView: View {
    @State private var selection: HelpTopic = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                HelpContent(topic: selection)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 560)
        .navigationTitle("Modo Help")
    }
}

// MARK: - Reusable building blocks

/// Bold heading inside a topic.
private struct H2: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.headline)
            .padding(.top, 4)
    }
}

/// A bullet item with a leading dot.
private struct Bullet<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            content()
        }
    }
}

/// A shortcut combo on the left, action on the right.
private struct KeyRow: View {
    let combo: String
    let action: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(combo)
                .font(.callout.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: .quaternaryLabelColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 110, alignment: .leading)
            Text(action).font(.callout)
            Spacer()
        }
    }
}

/// A boxed callout for tips / notes.
private struct Callout<Content: View>: View {
    let symbol: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Per-topic content

struct HelpContent: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(topic.title, systemImage: topic.symbol)
                .font(.title2.weight(.semibold))
                .padding(.bottom, 4)

            Group {
                switch topic {
                case .gettingStarted:       gettingStarted
                case .threeWays:            threeWays
                case .modesExplained:       modesExplained
                case .customModes:          customModes
                case .providers:            providers
                case .routing:              routing
                case .personalInstructions: personalInstructions
                case .generation:           generation
                case .privacy:              privacy
                case .permissions:          permissions
                case .troubleshooting:      troubleshooting
                case .shortcuts:            shortcuts
                case .about:                about
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    // MARK: Getting Started

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modo rewrites text you select, anywhere on your Mac. Three short steps:")

            Bullet { Text("**Select text** in any app — an email, a document, a browser field.") }
            Bullet { Text("**Open Modo** — click the **M** in the menu bar, or press your global hotkey (default ⌥ Space).") }
            Bullet { Text("**Pick a mode** — Modo streams the rewrite. Replace your selection or copy the result.") }

            Callout(symbol: "lightbulb", tint: .yellow) {
                Text("After running a mode once, the last-used mode is highlighted. Press **Return** the next time to repeat it instantly.")
            }
        }
    }

    // MARK: Three Ways to Use Modo

    private var threeWays: some View {
        VStack(alignment: .leading, spacing: 12) {
            H2("Global hotkey (recommended)")
            Text("Select text in any app, then press your configured global hotkey to open Modo with that text pre-loaded. Default is **⌥ Space** — change it in Preferences → Global Hotkey. The current hotkey is also shown in the menu-bar icon's tooltip.")

            H2("Per-mode hotkeys")
            Text("Bind a key combination to a specific mode in Preferences → Configure Per-Mode Hotkeys. Pressing it skips the menu and runs that mode directly on your selection.")

            H2("Right-click → Services → Improve with Modo")
            Text("In any app, right-click your selected text and pick **Services → Improve with Modo**. The popover opens pre-loaded with your selection — works even in apps that don't expose Accessibility text APIs (Notes, Mail, Slack, etc.). You can assign a system shortcut to this Service in **System Settings → Keyboard → Keyboard Shortcuts → Services**.")

            H2("Menu bar icon")
            Text("Click the **M** in the menu bar to open the utility menu (Open Modo, Preferences, History, Help, Check for Updates, Quit). Choose **Open Modo** to launch the popover when no text is selected.")

            H2("Inside the popover")
            Text("Once the popover is open:")
            Bullet { Text("**Return** — run the last-used mode (defaults to Improve when nothing is focused).") }
            Bullet { Text("**↑ / ↓** — move focus between the primary tiles and the secondary mode list.") }
            Bullet { Text("**⌘ 1 – ⌘ 9** — run the first nine secondary modes directly.") }
            Bullet { Text("**Escape** — close the popover.") }
            Bullet { Text("**Drag text** from any app onto the popover to use it as the input instead of the captured selection.") }
        }
    }

    // MARK: Modes Explained

    private var modesExplained: some View {
        VStack(alignment: .leading, spacing: 12) {
            Bullet { Text("**Improve** — clarity, flow, and word choice. Fixes grammar along the way and keeps tone.") }
            Bullet { Text("**Fix Grammar** — corrects spelling, grammar, and punctuation only. Won't restyle.") }
            Bullet { Text("**Make Formal** — professional / academic tone. Replaces contractions and casual phrasing.") }
            Bullet { Text("**Make Casual** — friendlier, conversational tone with contractions.") }
            Bullet { Text("**Make Concise** — tightens the prose without losing information.") }
            Bullet { Text("**Rephrase** — same meaning, different words. Useful for avoiding repetition.") }
            Bullet { Text("**Ask AI** — your selection is treated as a direct instruction. Best for free-form prompts (\"Make this a bullet list\", \"Translate to French\").") }

            Callout(symbol: "checkmark.seal", tint: .green) {
                Text("Modo always asks the model to return **only** the rewritten text — no preamble, no quotes, no commentary.")
            }
        }
    }

    // MARK: Custom Modes

    private var customModes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create your own rewrite shortcuts in Preferences → Custom Modes → **Manage Custom Modes…**.")

            H2("Fields")
            Bullet { Text("**Name** — appears in the popover grid.") }
            Bullet { Text("**Icon** — choose an SF Symbol.") }
            Bullet { Text("**System Prompt** — your instruction to the model.") }
            Bullet { Text("**Output Language** — force the result to a specific language (great for translation modes).") }
            Bullet { Text("**Treat as direct instruction** — when on, your selected text is sent as-is, like Ask AI. When off, it's wrapped in `<text>` tags so the model treats it as content to edit.") }

            H2("Examples")
            Bullet { Text("\"Translate to German\" — with Output Language set to German.") }
            Bullet { Text("\"Reply politely declining\" — direct instruction mode.") }
            Bullet { Text("\"Convert to bullet points\" — content-editing mode.") }
            Bullet { Text("\"Tweet this\" — instructs the model to compress to ≤ 280 chars.") }
        }
    }

    // MARK: AI Providers

    private var providers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modo never has its own account — you bring your own API key from one of these providers. Keys live in the macOS Keychain.")

            H2("Groq")
            Bullet { Text("Free tier, very fast inference. Keys look like `gsk_…`.") }
            Link("Get a key at console.groq.com", destination: URL(string: "https://console.groq.com")!)

            H2("OpenAI")
            Bullet { Text("Paid (`sk-…`). GPT-4o and GPT-4o mini.") }
            Link("Get a key at platform.openai.com", destination: URL(string: "https://platform.openai.com")!)

            H2("Anthropic")
            Bullet { Text("Paid (`sk-ant-…`). Claude Sonnet/Haiku/Opus.") }
            Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com")!)

            H2("Google Gemini")
            Bullet { Text("Free tier (`AIza…`). Gemini 2.0 Flash and 2.5 Pro.") }
            Link("Get a key at aistudio.google.com", destination: URL(string: "https://aistudio.google.com")!)

            H2("Ollama (local)")
            Text("Run open-weights models entirely on your Mac. **Your text never leaves the machine** and there's nothing to pay for after install.")
            Bullet { Text("Install: `brew install ollama`, or download from ollama.com.") }
            Bullet { Text("Start: `ollama serve` in Terminal, or launch the Ollama app.") }
            Bullet { Text("Pull a model: `ollama pull llama3.2` (or qwen2.5, mistral, phi3.5, …).") }
            Bullet { Text("Suggested: **llama3.2** for general rewrites, **qwen2.5** for code/structured text, **mistral** for fast/small.") }
            Bullet { Text("Endpoint defaults to `http://localhost:11434/v1/chat/completions` — change it in Preferences if you customized your install.") }
            Link("Download Ollama", destination: URL(string: "https://ollama.com")!)

            Callout(symbol: "info.circle", tint: .blue) {
                Text("If Modo says \"Ollama doesn't appear to be running,\" open Terminal and run `ollama serve`, or launch the Ollama app.")
            }

            H2("Custom (OpenAI-compatible)")
            Text("Point Modo at any OpenAI-compatible chat completions endpoint — OpenRouter, Together AI, Fireworks, Azure OpenAI, a local LiteLLM proxy, your own server. Provide the full URL and a model identifier the endpoint expects.")
        }
    }

    // MARK: Per-Mode Routing

    private var routing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In Preferences → Model → **Per-Mode Routing…**, you can send each mode to a different (provider, model) than the global default. This is the cost-saving recipe Modo enables that Grammarly can't.")

            H2("A common setup")
            Bullet { Text("**Fix Grammar → Groq + GPT OSS 20B** — cheap and instant for the most-used mode.") }
            Bullet { Text("**Improve → Anthropic + Claude Sonnet 4.6** — strong for nuanced rewrites.") }
            Bullet { Text("**Ask AI → OpenAI + GPT-4o** — best general reasoning.") }
            Bullet { Text("**Make Concise → Ollama + llama3.2** — free and local for short tasks.") }

            Callout(symbol: "lightbulb", tint: .yellow) {
                Text("Leave a row on \"Default\" to use whichever provider/model is selected globally.")
            }
        }
    }

    // MARK: Personal Instructions

    private var personalInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A persistent instruction appended to **every** mode's prompt. Use it for things that should always apply, regardless of which mode you pick.")

            H2("Examples")
            Bullet { Text("\"I'm British — keep -our spellings (colour, favour).\"") }
            Bullet { Text("\"Never use em-dashes.\"") }
            Bullet { Text("\"Always capitalize Acme product names exactly as written: Acme Forge, Acme Mill.\"") }
            Bullet { Text("\"Prefer active voice.\"") }
            Bullet { Text("\"Avoid the words 'leverage', 'utilize', 'synergy'.\"") }
        }
    }

    // MARK: Tone, Diff & Generation

    private var generation: some View {
        VStack(alignment: .leading, spacing: 12) {
            H2("Tone Detection")
            Text("When the popover opens with a selection, Modo can ask the model to summarize how your text reads — a single short sentence shown above the mode grid. Useful when you're not sure what to fix. Toggle in Preferences → Tone Detection. Costs one small extra API call per open.")

            H2("Diff view")
            Text("On the result screen, click the **rectangle.split.2x1** icon in the header to see exactly what changed: removed words appear red with strikethrough, added words appear green underlined. Disabled for **Ask AI** since there's no meaningful comparison.")

            H2("Creativity")
            Text("Lower temperature gives predictable, conservative edits. Higher temperature lets the model rephrase more freely. Default 0.7 is balanced.")

            H2("Length")
            Bullet { Text("**Short** — ~512 tokens. Best for grammar fixes and quick rephrasings.") }
            Bullet { Text("**Medium** — ~2048 tokens. Default. Good for most paragraphs.") }
            Bullet { Text("**Long** — ~4096 tokens. Use for long-form content.") }

            H2("Regenerate & Try a Different Model")
            Text("Click the **arrow.clockwise** button on the result screen to regenerate with the same model, or open its menu to try a different model from the current provider — useful when the first answer isn't quite right.")
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modo has **no account and no server of its own**. The only things that leave your Mac are:")

            Bullet { Text("**Your selected text**, sent to the AI provider you chose.") }
            Bullet { Text("**Your API key**, used to authenticate that request.") }
            Bullet { Text("Nothing else — no usage analytics, no telemetry, no crash reporting.") }

            H2("What's stored locally")
            Bullet { Text("**API keys** — encrypted in the macOS Keychain.") }
            Bullet { Text("**Settings** — UserDefaults (custom modes, hotkeys, generation controls).") }
            Bullet { Text("**History** — local UserDefaults, capped at the most recent 20 rewrites. Clear it anytime from the History window.") }

            Callout(symbol: "lock.shield", tint: .green) {
                Text("Using **Ollama** as the provider keeps everything on-device — your text doesn't go to any external service at all.")
            }
        }
    }

    // MARK: Permissions

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modo needs one macOS permission to do its job: **Accessibility**.")

            H2("Why")
            Bullet { Text("**Read** — get the text you've selected in any app.") }
            Bullet { Text("**Write** — replace your selection with the improved text.") }

            H2("How to grant")
            Bullet { Text("System Settings → Privacy & Security → Accessibility.") }
            Bullet { Text("Find **Modo** in the list and turn its switch on.") }
            Bullet { Text("If you don't see Modo, drag it in from /Applications, or quit and reopen so it appears.") }

            Callout(symbol: "exclamationmark.triangle", tint: .orange) {
                Text("If you revoke Accessibility while Modo is running, Replace will fall back to copying the result to your clipboard. The popover will tell you to re-enable Accessibility in System Settings.")
            }
        }
    }

    // MARK: Troubleshooting

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\"Select some text first\"").font(.callout.weight(.medium))
                Text("Modo didn't see a selection. Highlight text in any app, then open Modo. If you click outside the editor before opening Modo, the selection can be cleared — the menu-bar click is designed not to steal focus, so usually just clicking M works.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\"Add your API key in Preferences\"").font(.callout.weight(.medium))
                Text("No key is saved for the selected provider. Open Preferences → API Key and paste one. (Ollama doesn't need a key.)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\"Your API key looks invalid or expired\"").font(.callout.weight(.medium))
                Text("The provider returned 401/403. Re-check the key in Preferences or generate a new one from the provider's dashboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\"Rate limit or quota reached\"").font(.callout.weight(.medium))
                Text("HTTP 429. Wait a moment, switch to a different model in Preferences, or check your provider account for credit/quota status.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\"Ollama doesn't appear to be running\"").font(.callout.weight(.medium))
                Text("Start it with `ollama serve` in Terminal, or launch the Ollama app. Then try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\"The provider stopped responding\"").font(.callout.weight(.medium))
                Text("Modo gives up after 45 seconds without progress. Check your network, try a different model, or switch providers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Replace didn't change my text").font(.callout.weight(.medium))
                Text("Some apps (Notes, Mail, some web/Electron editors) block programmatic text replacement. Modo falls back to copying the result to your clipboard — just paste it with ⌘ V.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("I don't see the icon").font(.callout.weight(.medium))
                Text("Modo has no Dock icon by design — look in the menu bar at the top-right. If your menu bar is crowded, hold ⌘ and drag icons to make room.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Keyboard Shortcuts

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 6) {
            KeyRow(combo: "⌥ Space", action: "Open Modo (configurable)")
            KeyRow(combo: "Esc",     action: "Close the popover")
            KeyRow(combo: "Return",  action: "Repeat the last-used mode")
            KeyRow(combo: "⌘ 1 – ⌘ 9", action: "Run mode 1 through 9 in the grid")
            KeyRow(combo: "⌘ ,",     action: "Open Preferences (from context menu)")
            KeyRow(combo: "⌘ H",     action: "Open History (from context menu)")
            KeyRow(combo: "⌘ Q",     action: "Quit Modo (from context menu)")

            Divider().padding(.vertical, 6)

            Text("Per-mode hotkeys").font(.headline)
            Text("Set any combination per mode in Preferences → Configure Per-Mode Hotkeys. The bound combo is shown next to the mode name in the popover.")

            Callout(symbol: "command", tint: .blue) {
                Text("All hotkeys require at least one modifier (⌃ ⌥ ⇧ ⌘) so they don't clash with normal typing.")
            }
        }
    }

    // MARK: About

    private var about: some View {
        AboutSection(versionString: versionString)
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// Pulled out so it can observe `UpdaterService` and reactively enable/disable
/// the Check for Updates button as Sparkle's `canCheckForUpdates` changes.
private struct AboutSection: View {
    let versionString: String
    @ObservedObject private var updater = UpdaterService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modo")
                        .font(.title3.weight(.semibold))
                    Text("Version \(versionString)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Modo is a focused macOS menu-bar app that rewrites the currently-selected text using an AI provider of your choice. Free, your own keys, no server.")

            HStack(spacing: 12) {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!updater.canCheckForUpdates)
                Spacer()
            }

            Text("Copyright © 2026. All rights reserved.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
