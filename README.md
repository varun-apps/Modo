# Modo

**Modo** is a focused macOS menu-bar app that rewrites any text you select, anywhere on your Mac, using an AI provider of your choice. Free, your own API keys, no server.

Select text → press a hotkey (or click the **M** in the menu bar) → pick a mode → Modo streams the rewrite back. Replace your selection in place, or copy the result.

---

## Highlights

- **Six built-in modes** + **Ask AI** for free-form instructions: Improve, Fix Grammar, Make Formal, Make Casual, Make Concise, Rephrase, Ask AI.
- **Custom modes** — define your own ("Translate to German", "Reply politely declining", "Convert to bullet list") with their own icons, prompts, and output language.
- **Six providers** — Groq, OpenAI, Anthropic, Google Gemini, **Ollama** (local, fully offline), or any **OpenAI-compatible** endpoint.
- **Per-mode model routing** — send Fix Grammar to a cheap fast model, Improve to a strong one. Save tokens.
- **Global hotkey** (default ⌥Space) and **per-mode hotkeys** so any rewrite is one keystroke away.
- **Tone detection**, **inline word diff**, **personal instructions** that apply to every mode, adjustable **creativity & length**.
- **History** of recent rewrites (searchable), **Undo Replace** for 30 s, **Save as Custom Mode** to reuse a mode you tweaked.
- **In-app Help** window, **first-run onboarding** wizard, **Open at Login**, **Settings export/import**.
- **Sparkle 2** auto-updates from GitHub Releases. Signed, notarized, EdDSA-verified.
- **Privacy by design** — no account, no telemetry. Your keys live in the Keychain. With Ollama, your text never leaves your Mac.

---

## Install

1. Open **Modo.dmg** and drag Modo to your **Applications** folder.
2. Launch Modo — the **M** icon appears in your menu bar.
3. If macOS warns about an internet download, click **Open**.
4. The first-run **Welcome** wizard walks you through API key setup and Accessibility permission.

---

## First-time setup

### 1. Pick a provider and add your API key

In the Welcome wizard (or later in **Preferences**), pick a provider and paste your key. Modo stores it in the **macOS Keychain** — never on disk in plain text.

| Provider | Cost | Key prefix | Where to get one |
|---|---|---|---|
| **Groq** | Free tier, very fast | `gsk_…` | [console.groq.com](https://console.groq.com) |
| **Google Gemini** | Free tier | `AIza…` | [aistudio.google.com](https://aistudio.google.com) |
| **OpenAI** | Paid | `sk-…` | [platform.openai.com](https://platform.openai.com) |
| **Anthropic** | Paid | `sk-ant-…` | [console.anthropic.com](https://console.anthropic.com) |
| **Ollama** (local) | Free after install | not required | [ollama.com](https://ollama.com) |
| **Custom** | Depends | optional | Any OpenAI-compatible endpoint (OpenRouter, Together, Azure, LiteLLM proxy, etc.) |

### 2. Grant Accessibility permission

Modo needs **Accessibility** to read the text you select and to write the improved text back. The Welcome wizard will open System Settings for you, or:

1. **System Settings → Privacy & Security → Accessibility**
2. Find **Modo** in the list and turn its switch on.
3. Quit and reopen Modo if it was already running.

---

## How to use

### Three ways to launch

- **Menu-bar click** — click the **M** in the menu bar.
- **Global hotkey** — press your configured hotkey (default **⌥ Space**) from any app.
- **Per-mode hotkey** — bind, e.g., `⌃⌘G` to Fix Grammar in **Preferences → Configure Per-Mode Hotkeys**, and it skips the menu and runs directly.

### Inside the popover

- **⌘1 – ⌘9** — run the first nine modes directly.
- **Return** — repeat the last-used mode (it's highlighted).
- **Escape** — close the popover.
- **Drag text** from any app onto the popover to use it as the input.

### Result actions

- **Replace** — write the improved text over your original selection.
- **Copy** — put the result on the clipboard.
- **Regenerate** (↻) — re-run; long-press to **Try a Different Model** from the current provider.
- **Diff toggle** — see exactly what changed (red strikethrough = removed, green underlined = added).
- **Bookmark** — save the current mode as a new Custom Mode.
- **Undo** — within 30 seconds of a successful Replace, revert your selection back to the original.

---

## Power-user features

**Custom modes** — Preferences → Custom Modes → Manage. Set name, icon, prompt, output language, and whether the selection is a direct instruction (like Ask AI) or content to edit.

**Per-mode model routing** — Preferences → Model → Per-Mode Routing. Cheap-fast model for grammar fixes, strong model for the rewrites that matter.

**Personal instructions** — Preferences → Personal Instructions. Free-form text appended to every prompt. Examples: *"I'm British — keep -our spellings"*, *"Never use em-dashes"*, *"Always capitalize Acme product names"*.

**Generation controls** — adjust creativity (temperature) with a slider, and pick Short / Medium / Long output length.

**Tone detection** — when you open the popover, Modo can run a small extra call to describe how your text reads ("This sounds blunt", "This reads as enthusiastic"). Toggle in Preferences.

**Ollama (fully local)** — install Ollama, run `ollama serve`, pull a model (`ollama pull llama3.2`). Your text never leaves your Mac and there's nothing to pay for after install.

**History** — right-click the M → **History…**. Searchable list of the last 20 rewrites with one-click copy of original or result.

**Settings export/import** — Preferences → Backup → Export. Saves your modes, hotkeys, routing, generation controls, and personal instructions as JSON. (API keys are deliberately excluded — they stay in the Keychain.)

**Open at Login** — Preferences → Startup. Uses `SMAppService` (macOS 13+).

**Auto-updates** — Modo uses Sparkle 2. Toggle "Check for updates automatically" in Preferences → Updates, or check manually any time from Help → About or the context menu.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **⌥ Space** | Open Modo (configurable) |
| **Esc** | Close the popover |
| **Return** | Repeat the last-used mode |
| **⌘ 1 – ⌘ 9** | Run mode 1 through 9 in the grid |
| **⌘ ,** | Open Preferences (from context menu) |
| **⌘ H** | Open History (from context menu) |
| **⌘ Q** | Quit Modo (from context menu) |
| Per-mode bindings | Whatever you configure in Preferences |

---

## Privacy

- **No account, no server, no telemetry.** Modo never phones home.
- **API keys** stay in the macOS Keychain.
- **Your selected text** is sent only to the AI provider you chose, when you trigger a rewrite. Nothing else.
- **History** is stored locally in `UserDefaults`, capped at 20 entries, clearable any time.
- With **Ollama** as your provider, your text doesn't leave your Mac at all.

---

## Troubleshooting

| Issue | Fix |
|---|---|
| *"Select some text first"* | Highlight text before opening Modo |
| *"Add your API key in Preferences"* | Right-click M → Preferences → paste your key (or pick Ollama, which doesn't need one) |
| *"Your API key looks invalid or expired"* | Provider returned 401/403 — re-check the key in Preferences |
| *"Rate limit or quota reached"* | Wait, switch models, or check your provider account |
| *"Ollama doesn't appear to be running"* | Run `ollama serve` in Terminal, or launch the Ollama app |
| *"The provider stopped responding"* | Modo gives up after 45 s of silence — retry, switch model, or check your network |
| Replace didn't change the text | Some apps (Notes, Mail, Electron editors) block replacement — Modo copies to clipboard instead; paste with ⌘V |
| Accessibility not reading the selection | System Settings → Privacy & Security → Accessibility → turn Modo on, then relaunch |
| Icon not visible | Top-right of the menu bar — Modo has no Dock icon by design |
| Hotkey "already in use" warning | Pick a different combo; macOS reserves many shortcuts (Spotlight, Mission Control, etc.) |

More detailed guidance lives inside the app — right-click M → **Help…**.

---

## Building from source

```bash
git clone https://github.com/varun-apps/Modo.git
cd Modo
open Modo.xcodeproj
```

Press **⌘R** in Xcode. Sparkle is included as a Swift Package dependency and will resolve automatically. Requires macOS 13+ and Xcode 16+.

---

## License

Copyright © 2026. See `LICENSE` for terms.
