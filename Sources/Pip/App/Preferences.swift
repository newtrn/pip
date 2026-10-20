import Combine
import PipCore
import SwiftUI

enum PipStyle: String, CaseIterable, Identifiable {
    case companion = "A", energy = "B", type = "C", hybrid = "H"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .companion: return "Companion"
        case .energy: return "Energy"
        case .type: return "Type"
        case .hybrid: return "Hybrid"
        }
    }
    /// Styles that put Pip (rather than bars or type) front and centre.
    var showsMascot: Bool { self == .companion || self == .hybrid }
}

enum MenuBarLayout: String, CaseIterable, Identifiable {
    case mascot, mascotPct, multi, animated, ultra
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mascot: return "Mascot"
        case .mascotPct: return "+ %"
        case .multi: return "All"
        case .animated: return "Rotate"
        case .ultra: return "Tiny"
        }
    }
}

enum IconColor: String, CaseIterable, Identifiable {
    case never, attention, always
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never: return "Never"
        case .attention: return "When low"
        case .always: return "Always"
        }
    }
}

enum AnimationIntensity: String, CaseIterable, Identifiable {
    case off, gentle, lively
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// User settings, persisted in UserDefaults. Every property writes through on change.
@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var style: PipStyle { didSet { save(style.rawValue, "style") } }
    @Published var menuBarLayout: MenuBarLayout { didSet { save(menuBarLayout.rawValue, "menuBarLayout") } }
    @Published var showUsed: Bool { didSet { save(showUsed, "showUsed") } }
    @Published var compact: Bool { didSet { save(compact, "compact") } }
    @Published var mascotOn: Bool { didSet { save(mascotOn, "mascotOn") } }
    @Published var iconColor: IconColor { didSet { save(iconColor.rawValue, "iconColor") } }
    @Published var animation: AnimationIntensity { didSet { save(animation.rawValue, "animation") } }
    @Published var touchBarEnabled: Bool { didSet { save(touchBarEnabled, "touchBarEnabled") } }
    /// Opt-in: keep Pip in the Touch Bar's Control Strip (private API).
    @Published var controlStrip: Bool { didSet { save(controlStrip, "controlStrip") } }
    @Published var notifyLow: Bool { didSet { save(notifyLow, "notifyLow") } }
    @Published var notifyReset: Bool { didSet { save(notifyReset, "notifyReset") } }
    @Published var notifyDisconnect: Bool { didSet { save(notifyDisconnect, "notifyDisconnect") } }
    @Published private(set) var enabled: [ProviderID] { didSet { save(enabled.map(\.rawValue), "enabledProviders") } }
    @Published var active: ProviderID { didSet { save(active.rawValue, "activeProvider") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func str(_ k: String) -> String? { defaults.string(forKey: k) }
        func bool(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: k) as? Bool ?? d }
        style = str("style").flatMap(PipStyle.init) ?? .hybrid
        menuBarLayout = str("menuBarLayout").flatMap(MenuBarLayout.init) ?? .mascotPct
        showUsed = bool("showUsed", false)
        compact = bool("compact", false)
        mascotOn = bool("mascotOn", true)
        iconColor = str("iconColor").flatMap(IconColor.init) ?? .attention
        animation = str("animation").flatMap(AnimationIntensity.init) ?? .gentle
        touchBarEnabled = bool("touchBarEnabled", true)
        controlStrip = bool("controlStrip", false)
        notifyLow = bool("notifyLow", true)
        notifyReset = bool("notifyReset", true)
        notifyDisconnect = bool("notifyDisconnect", false)
        let stored = (defaults.stringArray(forKey: "enabledProviders") ?? []).compactMap(ProviderID.init)
        // Anthropic API starts hidden: three tabs is what the popover design was sized for.
        let enabledList = stored.isEmpty ? [.claudeCode, .codex, .openAIAPI] : stored
        enabled = enabledList
        active = str("activeProvider").flatMap(ProviderID.init).flatMap { enabledList.contains($0) ? $0 : nil } ?? enabledList[0]
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    /// Providers in canonical order, filtered to the visible ones.
    var visibleProviders: [ProviderID] { ProviderID.allCases.filter(enabled.contains) }

    func isEnabled(_ id: ProviderID) -> Bool { enabled.contains(id) }

    /// Pauses or resumes a provider. The last visible provider cannot be hidden.
    func toggle(_ id: ProviderID) {
        if let i = enabled.firstIndex(of: id) {
            guard enabled.count > 1 else { return }
            enabled.remove(at: i)
            if active == id { active = visibleProviders[0] }
        } else {
            enabled.append(id)
        }
    }
}
