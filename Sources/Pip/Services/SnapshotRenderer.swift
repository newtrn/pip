import AppKit
import PipCore
import SwiftUI

/// Development aid: `Pip --snapshot <dir>` renders the popover, menu bar
/// layouts, mascot moods and settings panes to PNGs in light and dark, then
/// quits. Used to compare the native UI against the design side by side.
@MainActor
final class SnapshotRenderer: NSObject, NSApplicationDelegate {
    private let out: URL
    private let defaults: UserDefaults
    private var prefs: Preferences!
    private var coordinator: UsageCoordinator!
    private var motion: MotionController!

    init(outputDirectory: URL) {
        out = outputDirectory
        defaults = UserDefaults(suiteName: "dev.pip.Pip.snapshot")!
        defaults.removePersistentDomain(forName: "dev.pip.Pip.snapshot")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        prefs = Preferences(defaults: defaults)
        prefs.animation = .off
        motion = MotionController(preferences: prefs)
        coordinator = UsageCoordinator(providers: ProviderID.allCases.map { MockUsageProvider($0) },
                                       cache: SnapshotCache(suiteName: "dev.pip.Pip.snapshot"))
        coordinator.refreshAll()
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            renderAll()
            NSApp.terminate(nil)
        }
    }

    private func renderAll() {
        // The README logo: a happy, mostly full Pip on a transparent background.
        render(SlimeView(mood: .healthy, level: 0.82, size: 160, style: .color(mood: .healthy, remaining: 82, hue: 45, dark: false), fps: nil)
                .padding(16), "logo", dark: false, transparent: true)
        for dark in [false, true] {
            let tag = dark ? "dark" : "light"
            for style in PipStyle.allCases {
                prefs.style = style
                render(popover, "popover-\(style.label.lowercased())-\(tag)", dark: dark)
            }
            prefs.style = .hybrid
            prefs.compact = true
            render(popover, "popover-hybrid-compact-\(tag)", dark: dark)
            prefs.compact = false
            prefs.active = .openAIAPI
            render(popover, "popover-hybrid-openai-\(tag)", dark: dark)
            prefs.active = .anthropicAPI
            render(popover, "popover-hybrid-spendonly-\(tag)", dark: dark)
            prefs.active = .claudeCode

            render(menuBarGallery, "menubar-\(tag)", dark: dark)
            render(moodGallery(dark: dark), "moods-\(tag)", dark: dark)
            render(TouchBarStrip(coordinator: coordinator, prefs: prefs, motion: motion).frame(width: 685).padding(6).background(Color.black),
                   "touchbar-\(tag)", dark: true)
            // Squeezed: the boxes must drop Pip before they truncate a name.
            render(TouchBarStrip(coordinator: coordinator, prefs: prefs, motion: motion).frame(width: 3 * TouchBarStrip.minBoxWidth + 10).padding(6).background(Color.black),
                   "touchbar-narrow-\(tag)", dark: true)
            render(settingsGallery, "settings-\(tag)", dark: dark)
        }
    }

    private var popover: some View {
        PopoverView(coordinator: coordinator, prefs: prefs, motion: motion, opaqueBackground: true).padding(20)
    }

    private var menuBarGallery: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PipStyle.allCases) { style in
                HStack(spacing: 18) {
                    Text(style.label).font(.system(size: 11)).frame(width: 80, alignment: .leading)
                    ForEach(MenuBarLayout.allCases) { layout in
                        MenuBarSample(coordinator: self.coordinator, prefs: self.prefs, motion: self.motion, style: style, layout: layout)
                    }
                }
            }
        }
        .padding(16)
    }

    private func moodGallery(dark: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(MascotMood.allCases, id: \.self) { mood in
                let rem = mood == .low ? 18 : mood == .exhausted || mood == .waiting ? 0 : mood == .moderate ? 45 : 85
                VStack(spacing: 6) {
                    SlimeView(mood: mood, level: Double(rem) / 100, size: 64, style: .color(mood: mood, remaining: rem, hue: 45, dark: dark), fps: nil)
                    SlimeView(mood: mood, level: Double(rem) / 100, size: 17,
                              style: .mono(ink: .primary, tint: rem <= 25 ? Palette(dark: dark).level(rem, hue: 45) : nil), fps: nil)
                    Text(mood.rawValue).font(.system(size: 10))
                }
            }
        }
        .padding(20)
    }

    private var settingsGallery: some View {
        VStack(spacing: 12) {
            GeneralPane(prefs: prefs, launchAtLogin: LaunchAtLogin())
            ProvidersPane(prefs: prefs, coordinator: coordinator, accounts: AccountManager(keychain: KeychainStore(service: "dev.pip.Pip.snapshot")))
            AppearancePane(prefs: prefs, motion: motion)
            AlertsPane(prefs: prefs)
        }
    }

    private func render<V: View>(_ view: V, _ name: String, dark: Bool, transparent: Bool = false) {
        let bg = transparent ? Color.clear : dark ? Color(rgba: 30, 30, 32) : Color(hex: 0xE6E4DF)
        let renderer = ImageRenderer(content: view.background(bg).environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("failed: \(name)")
            return
        }
        try? png.write(to: out.appendingPathComponent(name + ".png"))
        print("wrote \(name).png")
    }
}

/// One menu bar item rendered with a fixed style and layout.
private struct MenuBarSample: View {
    let coordinator: UsageCoordinator
    let prefs: Preferences
    let motion: MotionController
    let style: PipStyle
    let layout: MenuBarLayout

    var body: some View {
        let local = Preferences(defaults: UserDefaults(suiteName: "dev.pip.Pip.snapshot.menubar")!)
        local.style = style
        local.menuBarLayout = layout
        local.iconColor = prefs.iconColor
        return MenuBarItemView(coordinator: coordinator, prefs: local, motion: motion)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
    }
}
