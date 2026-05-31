# Modo

**Modo** is a macOS menu bar app that rewrites any text you select, in any app, using AI. Select text, pick a mode, and get an improved version instantly.

---

## How to Use

### 1. Install
- Open **Modo.dmg** and drag Modo to your **Applications** folder
- Launch Modo — **M** icon appears in your menu bar
- If macOS warns about an internet download, click **Open**

### 2. Add Your API Key (one-time setup)
- Right-click the Modo icon → **Preferences**
- Pick an AI provider from the dropdown:
  - **Groq** — free tier, fastest (`gsk_…`)
  - **Google Gemini** — free tier (`AIza…`)
  - **OpenAI** — paid (`sk-…`)
  - **Anthropic** — paid (`sk-ant-…`)
- Paste your API key and click **Save**
- Your key is stored securely in the macOS Keychain — never in a plain file

### 3. Grant Accessibility Permission (one-time setup)
- On first use, Modo will prompt you to enable Accessibility access
- Click **Open System Settings** → go to **Privacy & Security → Accessibility**
- Toggle **Modo** on (you may need your Mac password or Touch ID)
- Quit and reopen Modo if it was already running

### 4. Improve Your Text
- **Select any text** in any app (email, document, browser etc.)
- **Left-click** the Modo icon in the menu bar
- Choose a mode:
  - **Improve** — better clarity and flow
  - **Fix Grammar** — corrects grammar and spelling
  - **Make Formal** — more professional tone
  - **Make Casual** — friendlier, relaxed tone
  - **Make Concise** — shorter and tighter
  - **Rephrase** — same meaning, different wording
  - **Ask AI** — ask a question or give a custom instruction about your text
- The rewritten text streams in as it's generated

### 5. Use the Result
- **Replace** — writes the improved text directly over your original selection
- **Copy** — copies the result to clipboard so you can paste it manually
- **← Back** — go back and try a different mode
- Press **Escape** or click outside to dismiss the window

---

## Privacy

- Modo has no account and no server of its own
- Your API key stays in your Mac's Keychain
- Your text is sent only to the AI provider you chose — nowhere else

---

## Troubleshooting

| Issue | Fix |
|---|---|
| *"Select some text first"* | Highlight text before clicking the Modo icon |
| *"Add your API key in Preferences"* | Right-click icon → Preferences → paste your key |
| Improved text never appears | Check your internet connection and verify the API key is valid |
| Replace didn't work | Some apps block replacement — Modo copies to clipboard instead, just paste with ⌘V |
| Accessibility not reading selection | System Settings → Privacy & Security → Accessibility → turn Modo on, then relaunch |
| Icon not visible | Look in the top-right menu bar — Modo has no Dock icon by design |
