# Modo 1.1

## What's new

**New ways to invoke Modo**
- Floating **Modo bubble** next to your selected text (opt-in in Preferences → Selection Bubble)
- **"Improve with Modo"** in any app's right-click → Services menu — works even in Notes, Mail, Slack, and other non-AX apps
- ⌘1 – ⌘9 to run the first nine modes directly from the popover

**Power-user features**
- Per-mode model routing (cheap-fast model for grammar, strong model for rewrites)
- Tone detection, inline word diff, personal instructions, generation controls (temperature, length)
- Custom modes with output language and direct-instruction toggle
- Ollama (local, fully offline) and any OpenAI-compatible endpoint
- Searchable rewrite history, undo replace within 30 seconds, save result as custom mode

**Polish & reliability**
- In-app Help window with 13 topics
- First-run onboarding wizard
- Open at Login, Settings export/import
- Better error messages for 401 / 429 / network / Ollama-not-running
- Single Accessibility permission prompt instead of two
- Hotkey conflict warnings; modifier required (no more silently stealing Enter or Space)
- Bulletproof popover teardown — no more "Modo stops other apps from getting focus" issue
- Sparkle 2 auto-updates (this is the first update you'll get automatically!)

---

# Modo 1.0 — First public release

Modo is a macOS menu-bar app that rewrites any text you select, anywhere on your Mac, using an AI provider of your choice. Bring your own API key, no server, no account, no telemetry.

## Highlights

- **Six built-in modes** + **Ask AI** for free-form instructions — Improve, Fix Grammar, Make Formal, Make Casual, Make Concise, Rephrase, Ask AI.
- **Custom modes** with their own icons, prompts, and output language.
- **Six providers** — Groq, OpenAI, Anthropic, Google Gemini, Ollama (local, fully offline), or any OpenAI-compatible endpoint.
- **Per-mode model routing** — cheap-fast model for grammar, strong model for rewrites.
- **Global hotkey** (default ⌥Space) and **per-mode hotkeys** for one-keystroke rewrites.
- **Tone detection**, **inline word diff**, **personal instructions**, adjustable creativity & length.
- **History** of recent rewrites (searchable), **Undo Replace** for 30 s, **Save as Custom Mode**.
- **In-app Help**, **first-run onboarding wizard**, **Open at Login**, **Settings export/import**.
- **Sparkle 2** auto-updates from GitHub Releases — signed, notarized, EdDSA-verified.
- **Privacy by design** — no account, no telemetry. API keys live in the Keychain. With Ollama, your text never leaves your Mac.

## System requirements

- macOS 13 (Ventura) or later
- Apple silicon or Intel
- Accessibility permission (granted via first-run wizard)

## Install

1. Download **Modo-1.0.zip** below and unzip.
2. Drag **Modo.app** to **Applications**.
3. Launch — the **M** icon appears in your menu bar.
4. The first-run Welcome wizard walks you through API key setup and Accessibility permission.
