import SwiftUI
import AppKit
import PipCore

@main
enum PipMain {
    @MainActor
    static func main() {
        if let i = CommandLine.arguments.firstIndex(of: "--probe"), let name = CommandLine.arguments.dropFirst(i + 1).first {
            probe(name)
            return
        }
        let app = NSApplication.shared
        // A menu bar app: no Dock icon, no main menu.
        app.setActivationPolicy(.accessory)
        let delegate: NSApplicationDelegate
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let dir = CommandLine.arguments.dropFirst(i + 1).first ?? "snapshots"
            delegate = SnapshotRenderer(outputDirectory: URL(fileURLWithPath: dir))
        } else {
            delegate = AppDelegate()
        }
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// Development aid: `Pip --probe codex` prints what a real provider returns.
@MainActor
private func probe(_ name: String) {
    if name == "touchbar" {
        print("Touch Bar hardware: \(TouchBarController.isSupported) · Control Strip API: \(ControlStrip.isAvailable)")
        return
    }
    if name == "tbview" {
        let prefs = Preferences(), motion = MotionController(preferences: prefs)
        let coordinator = UsageCoordinator(providers: ProviderID.allCases.map { MockUsageProvider($0) })
        let host = NSHostingView(rootView: TouchBarStrip(coordinator: coordinator, prefs: prefs, motion: motion))
        host.frame = NSRect(x: 0, y: 0, width: 384, height: 30)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments.last!))
        return
    }
    guard let id = ProviderID(rawValue: name) else { print("Unknown provider \(name)"); exit(2) }
    let provider: any UsageProvider = switch id {
    case .codex: CodexProvider()
    case .claudeCode: ClaudeCodeProvider()
    case .openAIAPI: OpenAIAPIProvider(credentials: KeychainStore())
    case .anthropicAPI: AnthropicAPIProvider(credentials: KeychainStore())
    }
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let snap = try await provider.fetchUsage(now: Date())
            print("\(snap.plan) · observed \(snap.fetchedAt)")
            for m in snap.metrics { print("  \(m.label): \(m.value) resets \(m.resetsAt.map { "\($0)" } ?? "—")") }
        } catch {
            print("error: \(error)")
        }
        done.signal()
    }
    done.wait()
}
