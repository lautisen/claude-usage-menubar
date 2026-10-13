# Claude Usage — macOS menu bar app

A lightweight native macOS menu bar app that shows your **Claude plan usage limits** in real time: the current 5‑hour session, the weekly limit, per‑model weekly limits and extra usage — with countdowns to each reset.

> 🇪🇸 App nativa para la barra de menús de macOS que muestra en tiempo real el uso de los límites de tu plan de Claude (sesión de 5 h, semanal, por modelo y uso extra). La interfaz está en español.

<!-- Add a screenshot: ![Screenshot](docs/screenshot.png) -->

## Features

- **Menu bar indicator** — a custom two‑bar icon (5‑hour session + weekly) plus the session percentage and time until reset, e.g. `42% · 2h13m`. Turns orange at 75 % and red at 90 %.
- **Dropdown panel** with:
  - Current session (5‑hour window) with a live countdown and reset time
  - Weekly limit (all models) and per‑model weekly limits (Opus / Sonnet) when present
  - Breakdown of weekly usage by category
  - Extra usage credits vs. monthly limit, when enabled
- **Auto‑refresh** every 2 minutes, plus refresh on open if data is older than 30 s; visible countdown to the next refresh.
- **Launch at login** toggle (via `SMAppService`).
- No Dock icon (`LSUIElement`), no dependencies, ~600 lines of Swift.

## How it works

The app reuses the OAuth session that [Claude Code](https://claude.com/claude-code) already stores in the macOS Keychain (`Claude Code-credentials`), read through `/usr/bin/security` so no extra permission prompts appear. It then calls the usage endpoint that Claude Code itself uses (`/api/oauth/usage`) and decodes the response.

Your token never leaves your machine except in the request to `api.anthropic.com`.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`)
- Claude Code installed and logged in with a Claude subscription (`claude` → `/login`)

## Build & install

```sh
git clone https://github.com/lautisen/claude-usage-menubar.git
cd claude-usage-menubar
./build.sh            # builds build/ClaudeUsage.app
./build.sh install    # also copies it to ~/Applications and launches it
```

The build uses `swiftc` directly (no Xcode project) and ad‑hoc signs the bundle.

## Project structure

| File | Responsibility |
| --- | --- |
| `Sources/main.swift` | App delegate, status item, custom dropdown panel (`NSPanel`) and the menu bar icon drawing |
| `Sources/UsageStore.swift` | Observable state, refresh scheduling, launch‑at‑login |
| `Sources/UsageService.swift` | Keychain credential lookup, API request and `Decodable` models |
| `Sources/PopoverView.swift` | SwiftUI views for the dropdown |
| `build.sh` | Compiles and packages the `.app` bundle |

### Implementation notes

- **Custom panel instead of `NSPopover`**: `NSPopover` would partially render above the top edge of the screen when its content resized. A borderless `NSPanel` positioned manually always stays inside the visible frame and repositions itself as the SwiftUI content grows.
- **Date parsing**: the API returns microsecond fractions, which `ISO8601DateFormatter` rejects, so fractions are stripped before parsing.
- **Timeline‑driven UI**: countdowns use SwiftUI `TimelineView` so they tick without extra network requests.

## Disclaimer

This is an unofficial personal project, not affiliated with or endorsed by Anthropic. It relies on an undocumented endpoint that may change or stop working at any time.

## License

[MIT](LICENSE)
