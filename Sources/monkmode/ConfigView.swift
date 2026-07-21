import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ConfigView: View {
    @ObservedObject var model: AppModel
    @State private var minutes: Int = 50

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if model.isActive {
                    activeSession
                } else {
                    launcher
                }
                Divider()
                domainsSection
                appsSection
            }
            .padding(24)
        }
        .frame(minWidth: 460, minHeight: 560)
        .onAppear { minutes = model.config.presets.first ?? 50 }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isActive ? "lock.fill" : "lock.open")
                .font(.system(size: 26))
                .foregroundStyle(model.isActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("MonkMode").font(.system(size: 22, weight: .bold))
                Text(model.isActive ? "Session en cours" : "Tout est débloqué")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Session active

    private var activeSession: some View {
        VStack(spacing: 14) {
            Text(formatted(model.remaining))
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if model.isHardcoreLocked {
                Label("Mode hardcore — verrouillé jusqu'à la fin", systemImage: "lock.shield")
                    .foregroundStyle(.orange)
            } else {
                Button(role: .destructive) {
                    model.stop()
                } label: {
                    Text("Arrêter la session").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: Lancement

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper(value: $minutes, in: 5...600, step: 5) {
                Text("Durée : \(durationLabel(minutes))").font(.headline)
            }
            HStack {
                ForEach(model.config.presets, id: \.self) { p in
                    Button("\(p) min") { minutes = p }
                        .buttonStyle(.bordered)
                }
            }
            HStack {
                ForEach([120, 240, 360, 480, 600], id: \.self) { p in
                    Button(durationLabel(p)) { minutes = p }
                        .buttonStyle(.bordered)
                }
            }
            Toggle(isOn: Binding(
                get: { model.config.hardcore },
                set: { model.config.hardcore = $0; model.saveConfig() }
            )) {
                VStack(alignment: .leading) {
                    Text("Mode hardcore")
                    Text("Impossible d'arrêter avant la fin").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                model.start(minutes: minutes)
            } label: {
                Label("Démarrer la session", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.config.allowedApps.isEmpty && model.config.allowedDomains.isEmpty)
        }
    }

    // MARK: Sites autorisés

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sites autorisés").font(.headline)
            Text("Un domaine par ligne. Les sous-domaines sont inclus.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { model.config.allowedDomains.joined(separator: "\n") },
                set: { newValue in
                    model.config.allowedDomains = newValue
                        .split(whereSeparator: { $0 == "\n" || $0 == "," })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(height: 90)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            .disabled(model.isActive)
        }
    }

    // MARK: Apps autorisées

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Apps autorisées").font(.headline)
                Spacer()
                Button {
                    pickApps()
                } label: { Label("Ajouter…", systemImage: "plus") }
                .disabled(model.isActive)
            }
            if model.config.allowedApps.isEmpty {
                Text("Aucune app autorisée — tout sera fermé.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.config.allowedApps, id: \.self) { bid in
                HStack {
                    Text(appName(for: bid))
                    Text(bid).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.config.allowedApps.removeAll { $0 == bid }
                        model.saveConfig()
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(model.isActive)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Helpers

    private func formatted(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Durée lisible : "45 min", "1h30", "10h".
    private func durationLabel(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return String(format: "%dh%02d", h, m)
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !model.config.allowedApps.contains(id) {
                model.config.allowedApps.append(id)
            }
        }
        model.saveConfig()
    }
}
