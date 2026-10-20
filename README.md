<h1 align="center">
  <br>
  <a href="https://github.com/newtrn/pip"><img src="docs/logo.png" alt="Pip" width="160"></a>
  <br>
  Pip
  <br>
</h1>

<h4 align="center">A slime in your Mac's menu bar that watches your <a href="https://claude.com/claude-code" target="_blank">Claude Code</a>, <a href="https://openai.com/codex" target="_blank">Codex</a> and AI API usage.</h4>

<p align="center">
  <a href="https://github.com/newtrn/pip/releases/latest"><img src="https://img.shields.io/github/v/release/newtrn/pip?color=E07A4F" alt="Latest release"></a>
  <a href="https://github.com/newtrn/homebrew-tap"><img src="https://img.shields.io/badge/homebrew-newtrn%2Ftap%2Fpip-FBB040?logo=homebrew&logoColor=white" alt="Homebrew"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13 or later">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/newtrn/pip" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#install">Install</a> •
  <a href="#how-to-use">How To Use</a> •
  <a href="#build-from-source">Build From Source</a> •
  <a href="#privacy">Privacy</a> •
  <a href="#credits">Credits</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="docs/screenshots/popover-hybrid-light.png" width="380" alt="Pip's popover in light mode: 38% of the Claude session window left, with session, weekly and Opus limits">
  <img src="docs/screenshots/popover-hybrid-dark.png" width="380" alt="The same popover in dark mode">
</p>

## Key Features

* Your quota, at a glance
  - Pip fills up and drains with your remaining quota, gets sleepy while it waits for a reset, and cheers when a window refills.
* Four providers
  - **Claude Code**: 5-hour session and weekly limits.
  - **Codex**: 5-hour and weekly limits, plus credits.
  - **OpenAI API** and **Anthropic API**: spend this month, requests and tokens.
* Honest numbers
  - Quotas, API spend and credits are kept separate and never mixed. If a source fails, Pip says it's offline instead of guessing.
* Updates on its own
  - Refreshes in the background, again when you open it, and again after your Mac wakes.
* Four styles: Companion, Energy, Type and Hybrid
  - Plus five menu bar layouts, from Pip alone to every provider at once.
* Nine moods
  - Healthy, moderate, low, exhausted, waiting, recovered, disconnected, loading and stale.
* Touch Bar support
  - One box per provider. You can optionally keep Pip in the Control Strip and tap it to expand over any app.
* Notifications when you're running low (20% and 5%), when a window resets, and when a connection drops
* Dark/Light mode
* Light on battery
  - Animates in short bursts, stops drawing the popover when it's closed, and respects Reduce Motion. About 1–2% CPU when idle.
* Native macOS
  - Swift 6, SwiftUI and AppKit. No web view, no server, no dependencies.

<p align="center">
  <img src="docs/screenshots/menubar-light.png" width="720" alt="Menu bar layouts for each style">
  <br><br>
  <img src="docs/screenshots/moods-light.png" width="720" alt="Pip's nine moods">
</p>

## Install

Install with [Homebrew](https://brew.sh):

```bash
$ brew install --cask newtrn/tap/pip
```

You can also [download](https://github.com/newtrn/pip/releases/latest) the latest zip, unzip it and move **Pip.app** to Applications. It runs natively on both Apple silicon and Intel Macs, on macOS 13 Ventura or later.

> [!IMPORTANT]
> Pip isn't notarized by Apple yet. The first time you open it, macOS says it can't verify the developer. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once.

To update or remove Pip:

```bash
# Update to the latest version
$ brew upgrade --cask pip

# Remove Pip and its settings
$ brew uninstall --zap --cask pip
```

## How To Use

1. Open Pip. It lives in the menu bar and has no Dock icon.
2. Click Pip to see your usage. Every provider shows demo data until you connect it.
3. To open Settings, open the app again or click **Settings…** in the popover. Then go to **Providers → Connect…**:

| Provider | What Pip needs |
|---|---|
| **Claude Code** | Nothing. Pip uses the sign-in Claude Code already saved in your keychain, and macOS asks you once to allow it. |
| **Codex** | Nothing. Pip asks Codex through `codex app-server`, the way Codex's own apps do, so it never sees your token. Works with the Codex CLI or the Codex in ChatGPT.app. |
| **OpenAI API** | An [Admin key](https://platform.openai.com/settings/organization/admin-keys). Regular API keys can't read usage. |
| **Anthropic API** | An [Admin key](https://console.anthropic.com/settings/admin-keys) (`sk-ant-admin01-…`). |

> [!NOTE]
> The Claude Code and Codex sources are undocumented and could change without notice. If they do, Pip shows the provider as offline.

<p align="center">
  <img src="docs/screenshots/settings.png" width="520" alt="Pip's General settings">
  <br><br>
  <img src="docs/screenshots/touchbar.png" width="395" alt="Touch Bar with Claude and Codex boxes, each with a small Pip">
</p>

## Build From Source

To build Pip yourself, you'll need [Git](https://git-scm.com) and [Xcode](https://developer.apple.com/xcode/) 16 or later (Swift 6). From your command line:

```bash
# Clone this repository
$ git clone https://github.com/newtrn/pip

# Go into the repository
$ cd pip

# Build the app
$ scripts/build-app.sh

# Run the app
$ open build/Pip.app
```

Other useful commands:

```bash
# Run the unit tests
$ swift test

# Print what a real source returns (codex, claudeCode, openAIAPI or anthropicAPI)
$ swift run Pip --probe codex

# Render the popovers, menu bar, moods and Touch Bar to PNGs
$ swift run Pip --snapshot out/

# Build for Apple silicon and Intel, and zip it
$ UNIVERSAL=1 VERSION=0.2.0 scripts/build-app.sh
```

Pushing a `vX.Y.Z` tag builds the app on GitHub Actions and publishes a release. The [Homebrew tap](https://github.com/newtrn/homebrew-tap) picks up the new version within a few hours. For more detail, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Privacy

* Pip has no server and no analytics.
* API keys are stored in your login keychain and sent only to the provider they belong to.
* Pip never renews or changes the Claude Code or Codex sign-in.

## Credits

Pip uses no third-party packages. It's built with:

- [Swift](https://www.swift.org), [SwiftUI](https://developer.apple.com/xcode/swiftui/) and AppKit
- [OpenAI Admin API](https://platform.openai.com/docs/api-reference/usage) and [Anthropic Admin API](https://docs.anthropic.com/en/api/admin-api) for API usage and cost
- Community tools like [ccusage](https://github.com/ryoppippi/ccusage), which mapped out the Claude Code and Codex usage formats

## License

[MIT](LICENSE)

---

> GitHub [@newtrn](https://github.com/newtrn) &nbsp;&middot;&nbsp;
> Pip isn't affiliated with Anthropic or OpenAI. Claude, Claude Code, Codex and ChatGPT are their owners' trademarks.
