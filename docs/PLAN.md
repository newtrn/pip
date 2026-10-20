# Pip: status and next steps

See `ARCHITECTURE.md` for the structure and the design decisions.

## Build

```sh
./scripts/build-app.sh            # → build/Pip.app (release)
open build/Pip.app
build/Pip.app/Contents/MacOS/Pip --snapshot /tmp/pip-snaps   # PNGs of every surface, light and dark
```

The Xcode licence must be accepted once with `sudo xcodebuild -license accept`. `swift test` runs the unit tests. `Pip --probe codex|claudeCode|touchbar` prints what a real source returns.

## Done

- Menu bar item: four styles × five layouts, monochrome with a tint when low, and duty-cycled animation.
- Popover: Companion, Energy, Type and Hybrid headers; tabs, status banner, mascot tubes, metric rows, footer, compact mode, popIn animation, light and dark.
- Mascot: all nine moods, liquid level, blink, sleeping `z`, sweat drop, eased mood transitions.
- Settings window: General, Providers (pause/resume, demo controls), Appearance, Alerts.
- Coordinator: polling, cache to stale to offline, reset celebration, low and reset notifications.
- Touch Bar strip, shown while the popover is open, on supported Macs only.
- Launch at login through `SMAppService`.
- Measured idle cost: about 1–2 % CPU and about 20 MB of memory.
- Real data for the Anthropic API and the OpenAI API (Admin key, validated, stored in the keychain): Settings → Providers → Connect…. Both parsers are checked against the example payloads in the official docs.

## Next

1. Add an app icon and, if wanted, an Xcode project with an app target. SwiftPM with Swift 6 language mode already builds cleanly, and the 21 tests pass.
2. Check by hand in the real menu bar: alignment, the highlight while the popover is open, the Touch Bar on this MacBookPro17,1, and the Settings window sizing.
3. Check Claude Code against a live account: the usage endpoint is undocumented and its format has changed before.
4. Optional: SwiftData usage history with Swift Charts in the popover.
