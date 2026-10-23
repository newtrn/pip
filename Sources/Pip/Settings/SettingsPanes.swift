import PipCore
import SwiftUI

/// One settings row: right-aligned label and hint in a 200 pt column, control on the right.
struct PrefRow<Control: View>: View {
    var label: String
    var sub: String = ""
    @ViewBuilder var control: Control
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pf = PrefTokens.of(dark: scheme == .dark)
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(label)
                if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundColor(pf.sub) }
            }
            .frame(width: 200, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            control.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .overlay(Rectangle().fill(pf.hair).frame(height: 0.5), alignment: .bottom)
    }
}

private struct Pane<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .font(.system(size: 13))
            .toggleStyle(.switch)
            .tint(Palette.good)
            .padding(EdgeInsets(top: 18, leading: 26, bottom: 22, trailing: 26))
            .frame(width: 600)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func segmented<T: Hashable & Identifiable>(_ selection: Binding<T>, _ options: [T], label: @escaping (T) -> String) -> some View {
    Picker("", selection: selection) {
        ForEach(options) { Text(label($0)).tag($0) }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()
}

struct GeneralPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        Pane {
            // Hidden entirely, not disabled, on Macs without a Touch Bar.
            if TouchBarController.isSupported {
                PrefRow(label: "Show Pip in", sub: "Touch Bar detected on this Mac") {
                    Picker("", selection: $prefs.touchBarEnabled) {
                        Text("Menu Bar").tag(false)
                        Text("Menu Bar + Touch Bar").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            if TouchBarController.isSupported && ControlStrip.isAvailable {
                PrefRow(label: "Keep in Control Strip", sub: "Always on the Touch Bar, over any app. Tap Pip to expand. Uses a private macOS API that a future update could break.") {
                    Toggle("", isOn: $prefs.controlStrip).labelsHidden().disabled(!prefs.touchBarEnabled)
                }
            }
            PrefRow(label: "Numbers show", sub: "Applies everywhere") {
                Picker("", selection: $prefs.showUsed) {
                    Text("Remaining").tag(false)
                    Text("Used").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            PrefRow(label: "Compact mode", sub: "Fewer rows, tighter popover") {
                Toggle("", isOn: $prefs.compact).labelsHidden()
            }
            PrefRow(label: "Launch at login", sub: launchAtLogin.problem ?? "") {
                Toggle("", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) })).labelsHidden()
            }
        }
    }
}

struct ProvidersPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var coordinator: UsageCoordinator
    @ObservedObject var accounts: AccountManager
    @Environment(\.colorScheme) private var scheme
    @State private var connecting: ProviderID?

    var body: some View {
        let dark = scheme == .dark, pf = PrefTokens.of(dark: dark)
        Pane {
            VStack(spacing: 0) {
                ForEach(ProviderID.allCases) { q in
                    let s = coordinator.state(q), on = prefs.isEnabled(q)
                    HStack(spacing: 12) {
                        Text(s.descriptor.short).font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(oklch: dark ? 0.92 : 0.4, 0.12, s.hue))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(oklch: dark ? 0.4 : 0.92, 0.06, s.hue)))
                        VStack(alignment: .leading, spacing: 2) {
                            (Text(s.descriptor.name).fontWeight(.medium) + Text(" · " + (s.snapshot?.plan ?? "")).foregroundColor(pf.sub))
                            Text(s.descriptor.reports).font(.system(size: 11.5)).foregroundColor(pf.sub)
                        }
                        Spacer(minLength: 0)
                        let (dot, text) = statusLabel(s, on: on, pf: pf)
                        HStack(spacing: 5) {
                            Circle().fill(dot).frame(width: 6, height: 6)
                            Text(text)
                        }
                        .font(.system(size: 11.5)).foregroundColor(pf.sub)
                        if accounts.isConnected(q) {
                            Button("Disconnect") { accounts.disconnect(q, coordinator: coordinator) }
                        } else {
                            Button("Connect…") { connecting = q }
                        }
                        Button(on ? "Pause" : "Resume") { prefs.toggle(q) }
                            .disabled(on && prefs.visibleProviders.count == 1)
                    }
                    .padding(.vertical, 11).padding(.horizontal, 14)
                    .overlay(Rectangle().fill(pf.hair).frame(height: 0.5), alignment: .bottom)
                }
                Text("More providers are planned: Gemini, GitHub Copilot, Cursor.")
                    .font(.system(size: 12)).foregroundColor(pf.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10).padding(.horizontal, 14)
            }
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pf.card))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(pf.hair, lineWidth: 0.5))

            if coordinator.isDemo(prefs.active) {
                PrefRow(label: "Demo data", sub: "\(ProviderDescriptor.of(prefs.active).name) is showing demo numbers. These controls exercise Pip's reactions.") {
                    HStack {
                        Button("Simulate quota reset") { coordinator.simulateReset(prefs.active) }
                        Button("Simulate failure") { coordinator.simulateFailure(prefs.active) }
                    }
                }
                .padding(.top, 8)
            }
        }
        .sheet(item: $connecting) { id in
            ConnectSheet(provider: id, accounts: accounts, coordinator: coordinator) { connecting = nil }
        }
    }

    private func statusLabel(_ s: ProviderState, on: Bool, pf: PrefTokens) -> (Color, String) {
        guard on else { return (pf.sub, "Paused") }
        switch s.status {
        case .offline: return (Palette.bad, "Offline")
        case .stale: return (Palette.warn, "Stale")
        case .loading: return (Palette.good, "Syncing")
        case .paused: return (pf.sub, "Paused")
        case .live: return (Palette.good, s.snapshot?.isDemo == true ? "Demo" : "Connected")
        }
    }
}

struct AppearancePane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var motion: MotionController

    var body: some View {
        Pane {
            PrefRow(label: "Style") { segmented($prefs.style, PipStyle.allCases) { $0.label } }
            PrefRow(label: "Show mascot", sub: "Off = numbers only") { Toggle("", isOn: $prefs.mascotOn).labelsHidden() }
            PrefRow(label: "Menu bar") { segmented($prefs.menuBarLayout, MenuBarLayout.allCases) { $0.label } }
            PrefRow(label: "Icon color", sub: "Monochrome blends with macOS") { segmented($prefs.iconColor, IconColor.allCases) { $0.label } }
            PrefRow(label: "Animation", sub: motion.reduceMotion ? "Reduce Motion is on in System Settings" : "Off respects Reduce Motion") {
                segmented($prefs.animation, AnimationIntensity.allCases) { $0.label }
                    .disabled(motion.reduceMotion)
            }
        }
    }
}

struct AlertsPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Pane {
            PrefRow(label: "Running low", sub: "At 20% and 5% remaining") { Toggle("", isOn: $prefs.notifyLow).labelsHidden() }
            PrefRow(label: "Window reset", sub: "“Refilled!” when a quota resets") { Toggle("", isOn: $prefs.notifyReset).labelsHidden() }
            PrefRow(label: "Connection lost", sub: "After 3 failed refreshes") { Toggle("", isOn: $prefs.notifyDisconnect).labelsHidden() }
        }
    }
}

/// Connects one provider. API providers take an Admin key; Claude Code and
/// Codex reuse what is already on this Mac. Every path is checked with one
/// real fetch before Pip switches away from demo data.
struct ConnectSheet: View {
    let provider: ProviderID
    let accounts: AccountManager
    let coordinator: UsageCoordinator
    var dismiss: () -> Void

    @State private var key = ""
    @State private var error: String?
    @State private var checking = false

    private var name: String { ProviderDescriptor.of(provider).name }
    private var method: AccountManager.Method { AccountManager.method(for: provider) }

    private var explanation: String {
        switch provider {
        case .anthropicAPI:
            return "Create an Admin key (sk-ant-admin01-…) in Claude Console → Settings → Admin keys. Workspace API keys can't read usage."
        case .openAIAPI:
            return "Create an Admin key in the OpenAI dashboard → Organization → Admin keys. Project API keys can't read usage."
        case .claudeCode:
            return "Pip reads the sign-in Claude Code already saved in your keychain and asks api.anthropic.com for your 5-hour and weekly limits — the same request Claude Code makes. Pip never renews or changes that sign-in."
        case .codex:
            return "Pip asks Codex for your 5-hour and weekly limits by running codex app-server, the same way Codex's own apps do, using the sign-in Codex already has. Pip never sees that sign-in. If Codex can't be found, Pip reads the limits Codex records in ~/.codex/sessions instead."
        }
    }

    private var footnote: String {
        switch method {
        case .apiKey:
            return "Pip only reads organization costs and usage. The key stays in your login keychain and is sent only to \(provider == .anthropicAPI ? "api.anthropic.com" : "api.openai.com")."
        case .claudeCodeLogin, .codexLogin:
            return "This uses an undocumented format that may change without notice. If it does, Pip shows the provider as offline rather than guessing."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect \(name)").font(.system(size: 15, weight: .semibold))
            Text(explanation).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if method == .apiKey {
                SecureField("Admin key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
            }
            Text(footnote).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(.system(size: 12)).foregroundColor(Palette.bad).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if checking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled((method == .apiKey && key.trimmingCharacters(in: .whitespaces).isEmpty) || checking)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func connect() {
        guard !checking else { return }
        checking = true
        error = nil
        Task {
            let message = await accounts.connect(provider, key: method == .apiKey ? key : nil, coordinator: coordinator)
            checking = false
            if let message { error = message } else { dismiss() }
        }
    }
}
