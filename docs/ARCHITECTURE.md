# Pip: architecture

The design source of truth is the Claude Design prototype (`Prototype.dc.html`, `slime.js`). Local copies live in `design/`, which is not checked in. The recommended concept is the ★ Hybrid style, which is the default here.

## Layout

```
Sources/PipCore/           UI-free, testable
  Models/                  ProviderID, ProviderDescriptor, MetricValue, snapshots, ConnectionStatus
  Providers/               UsageProvider protocol, MockUsageProvider
  Mascot/                  MascotMood state machine and voice lines, SlimeGeometry (port of slime.js)
  Coordinator/             UsageCoordinator (polling, cache, events), UsagePresenter (strings and fractions)
  Support/                 OKLCH→sRGB, time formatting, SnapshotCache, KeychainStore
Sources/Pip/               AppKit + SwiftUI
  App/                     PipMain, AppDelegate (composition root), Preferences, ProviderState
  Theme/                   Palette (lc/pc/lcLight), popover and settings tokens, font mapping
  Mascot/                  SlimeView (Canvas + TimelineView), MotionController
  MenuBar/                 StatusItemController (NSStatusItem), MenuBarItemView
  Popover/                 PopoverPanel/Controller (borderless NSPanel), PopoverView
  Settings/                NSTabViewController window with four SwiftUI panes
  TouchBar/                TouchBarController and TouchBarStrip
  Services/                Notifications, launch at login, --snapshot renderer
Tests/PipCoreTests/        XCTest
```

## Design → native mapping

| Design | Native |
|---|---|
| `makeSlime` SVG path, rAF loop | `SlimeGeometry` (same maths) drawn in `Canvas`, driven by `TimelineView(.animation)` |
| CSS keyframes `pipBlink`, `pipZ` | Computed per frame from the wall clock (`blinkScale`), with the `z` drift in `drawFace` |
| `popIn` .22s cubic-bezier(.2,.9,.3,1) | `.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.22)` on opacity, scale and offset |
| `tickIn` (rotating layout) | `AnyTransition.tickIn`, a 5 pt fade-up |
| Segment `transition-delay` stagger | `.animation(...).delay(k * stagger)` per segment |
| `shimmer` on loading values | `ShimmerModifier` repeat-forever opacity |
| Popover card with blur and rim | Borderless `NSPanel` + `NSVisualEffectView(.popover)` + token overlay + 0.5 pt rim |
| OKLCH colors | `Color(oklch:)` converts exactly, no hand-picked approximations |
| Instrument Serif / IBM Plex Mono | New York (`.serif`) / SF Mono (`.monospaced`): no runtime font downloads |
| Settings window, 4 tabs | `NSTabViewController(.toolbar)` with SF Symbols; rows keep the 200 pt right-aligned label column |
| Touch Bar strip (1085×30 mock) | `NSCustomTouchBarItem` hosting `TouchBarStrip` |

### Deliberate deviations

- **Popover:** a borderless panel replaces `NSPopover`, because `NSPopover` always draws an arrow and the design has none. The panel is positioned 4 pt below the menu bar, with its right edge 96 pt past the status item, as in the prototype.
- **"Touch Bar only" mode removed:** without private Control Strip APIs, Pip would be unreachable in that mode. The setting is now *Menu Bar* or *Menu Bar + Touch Bar*, and it is hidden on Macs without a Touch Bar.
- **"+ Add provider…" link:** replaced by a plain note, because there is nothing to add yet and a dead control would mislead.
- **Demo data is always labelled:** the footer says "Demo data" and Settings → Providers shows "Demo".
- **Providers:** the design's Gemini card became *OpenAI API*, which shows the same kinds of values (daily requests, spend, an unknown TPM). *Anthropic API* is spend-only and starts hidden, because the popover was designed for three tabs.

## Provider interface

```swift
protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetchUsage(now: Date) async throws -> ProviderSnapshot
}
```

`MetricValue` keeps the different kinds of value apart: `quotaPercent`, `quotaCount`, `tally`, `spend`, `credits` and `unknown`. Only quota values feed the mascot. If a provider can't report a value, it returns `.unknown`, never an estimate. To add a provider:

1. Add a case to `ProviderID`.
2. Add a descriptor in `ProviderDescriptor.of`.
3. Write an implementation of `UsageProvider`.

The UI needs no changes.

## State flow

`UsageCoordinator` (`@MainActor ObservableObject`) owns snapshots, `ConnectionStatus` and the `recovering` set:

- It polls every 60 s and ticks a clock every 30 s for countdowns.
- After one or two failures it shows cached data as *stale*. After three it goes *offline* and hides the numbers.
- When the reset time moves forward and the remaining amount jumps by 30 points or more, it marks the provider as `recovered` for 3.6 s and emits `.windowReset`.
- Each low threshold (20 %, 5 %) emits `.runningLow` once.

`MascotMood.resolve` maps status, remaining amount, recovery and time-to-reset to one of the nine design moods. Views are pure functions of `UsageCoordinator`, `Preferences` and `MotionController`.

## Animation and power

- **Menu bar:** running continuous `TimelineView` frames cost about 10 % CPU, because the status bar window recomposites on every frame. Instead, Pip wakes for about 1.1 s of each 5.5 s blink cycle, ending just after the blink, and holds still in between. It moves continuously only while celebrating a refill.
- **Popover and Touch Bar:** 30 fps (Gentle) or 60 fps (Lively). The popover's view tree is unloaded when it closes, because an ordered-out window still runs its timelines.
- **No motion at all** when animation is set to Off, when Reduce Motion is on, or when the displays are asleep.
- **Measured** on an M1 MacBook Pro running the release build: about 1–2 % CPU idle and about 20 MB resident memory.

## Touch Bar constraints

The Touch Bar strip shows one usage box per visible provider: no lead mascot and no status line, per user feedback.

- **Opt-in "Keep in Control Strip" (off by default; private API):** `ControlStrip` loads DFRFoundation's `DFRElementSetControlStripPresenceForIdentifier` and NSTouchBar's `addSystemTrayItem:`, `presentSystemModalTouchBar:placement:systemTrayItemIdentifier:` and `dismissSystemModalTouchBar:` at runtime. Pip then stays in the Control Strip over any app, and tapping it expands the full strip. If any symbol is missing, the setting is hidden. While expanded, the strip animates in the same short bursts as the menu bar.


- An app's Touch Bar is shown only while that app is frontmost. Keeping it on screen over other apps needs `DFRFoundation`'s system-modal or Control Strip API, which is private and not used.
- While the popover is open with the Touch Bar enabled, Pip activates itself so the strip appears. When the popover closes, it hides itself, which returns focus to the previous app.
- Hardware detection uses `hw.model` against the known Touch Bar MacBook Pro models, because there is no public API for this.

## Real integrations

Each provider uses real data when an API key is connected and demo data otherwise. `AccountManager` makes that choice; `UsageCoordinator.replaceProvider` swaps the source and drops the old numbers, so demo and real values never mix.

| Provider | Source | Status |
|---|---|---|
| Anthropic API | `GET /v1/organizations/cost_report` (amount in cents, as a decimal string) and `GET /v1/organizations/usage_report/messages`. Uses `x-api-key` with an Admin key (`sk-ant-admin01-…`) and `anthropic-version: 2023-06-01` | **Implemented.** Shows month-to-date spend (UTC) and tokens today. There is no quota, so no percentage |
| OpenAI API | `GET /v1/organization/costs` (`amount.value` in dollars) and `GET /v1/organization/usage/completions`. Uses a Bearer Admin key | **Implemented.** Shows month-to-date spend, requests and tokens today. TPM stays `.unknown` |
| Claude Code | **Undocumented (approved):** `GET api.anthropic.com/api/oauth/usage` with Claude Code's own OAuth token from the keychain item `Claude Code-credentials`, plus `anthropic-beta: oauth-2025-04-20` and a `claude-code/…` User-Agent. The response's `limits[]` holds `kind`, `percent` and `resets_at`; the legacy flat `five_hour`/`seven_day*` keys are also handled | **Implemented.** Polls at most every 3 min. Never refreshes the token: Anthropic rotates refresh tokens, so a refresh racing Claude Code's own could sign Claude Code out. An expired token shows as offline with "Open Claude Code to renew it" |
| Codex | **Undocumented (approved):** Pip runs `codex app-server` (the JSON-RPC server Codex's own apps use) and calls `account/rateLimits/read`, which returns `primary`/`secondary` windows (`usedPercent`, `windowDurationMins`, `resetsAt`), `credits` and `planType`. The binary is found at `$CODEX_BIN`, inside ChatGPT.app, or on the usual install paths. Fallback: the `rate_limits` events in `~/.codex/sessions/**/*.jsonl` | **Implemented.** Codex answers with its own sign-in, so Pip never sees a token. Polled at most every 2 minutes. The log fallback shows the time of the last Codex turn as "Updated" |

- **Validating keys:** a key is checked with one real fetch before it is written to the login keychain (`KeychainStore`, service `dev.pip.Pip.credentials`). A 401 or 403 tells the user to use an Admin key.
- **Polling:** every 60 s, matching Anthropic's documented "once per minute" guidance.
- **Keychain prompts during development:** ad-hoc signed builds get a new code signature on every rebuild, so macOS may ask once per build before letting Pip read its keychain item.
