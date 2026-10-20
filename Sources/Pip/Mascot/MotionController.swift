import AppKit
import Combine

/// Decides how often mascots redraw. Animation stops entirely when the user
/// turns it off, when Reduce Motion is on, or when the displays are asleep, so
/// an idle Pip costs nothing.
@MainActor
final class MotionController: ObservableObject {
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published private(set) var displaysAsleep = false
    /// True during the short window each blink cycle when the menu bar Pip moves.
    @Published private(set) var menuBarAwake = false
    private var pulse: Timer?
    private var intensity: AnimationIntensity
    private var observers: [NSObjectProtocol] = []
    private var cancellable: AnyCancellable?

    init(preferences: Preferences) {
        intensity = preferences.animation
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.displaysAsleep = true }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.displaysAsleep = false }
        })
        cancellable = preferences.$animation.sink { [weak self] value in
            self?.intensity = value
            self?.objectWillChange.send()
        }
        startPulse()
    }

    /// Continuous animation in the menu bar costs ~10 % CPU even at 12 fps,
    /// because the status bar window recomposites every frame. Instead Pip
    /// wakes for ~1.1 s of each 5.5 s blink cycle (ending just after the blink)
    /// and holds still in between: it still reads as alive at a fifth of the cost.
    private func startPulse() {
        let cycle = 5.5, wakeAt = 4.4, sleepAt = 5.65
        pulse = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                let awake = self.animates && (phase >= wakeAt || phase < sleepAt - cycle)
                if awake != self.menuBarAwake { self.menuBarAwake = awake }
            }
        }
        pulse?.tolerance = 0.05
    }

    /// Whether anything should move at all.
    var animates: Bool { intensity != .off && !reduceMotion && !displaysAsleep }

    /// Frames per second for the 15–17 pt menu bar mascot. The blob moves
    /// slowly, so a low rate reads as smooth at that size.
    var menuBarFPS: Double? { animates ? (intensity == .lively ? 20 : 12) : nil }

    /// Frames per second for the popover and Touch Bar, which are only on screen briefly.
    var popoverFPS: Double? { animates ? (intensity == .lively ? 60 : 30) : nil }

    /// User-facing state for Settings: Reduce Motion forces Off.
    var effectiveIntensity: AnimationIntensity { reduceMotion ? .off : intensity }
}
