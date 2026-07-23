import AppKit

/// Masque en continu toute application GUI non autorisée (sans la fermer).
///
/// Sécurité : ne touche qu'aux apps « regular » (présence dans le Dock).
/// Les démons/agents système (.accessory, .prohibited) ne sont jamais touchés,
/// ce qui évite de casser macOS. Finder et MonkMode lui-même sont épargnés.
final class AppEnforcer {
    private var timer: Timer?
    private var allowed: Set<String> = []
    /// Relit la whitelist à chaque balayage -> rechargement à chaud : ajouter
    /// une app à la config est pris en compte en ~1 s, même en pleine session
    /// hardcore, sans redémarrer MonkMode.
    private var allowedProvider: () -> [String] = { [] }

    /// Bundle IDs toujours épargnés en plus de la whitelist utilisateur.
    /// Inclut Finder, Réglages système et les composants d'UI système
    /// pour ne jamais bloquer l'accès aux réglages de la machine.
    private let alwaysAllow: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",   // Réglages système (Ventura+)
        "com.apple.SystemPreferences",   // Préférences Système (anciens macOS)
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.WindowManager"
    ]

    func start(allowedProvider: @escaping () -> [String]) {
        self.allowedProvider = allowedProvider
        allowed = Set(allowedProvider())
        // Notification à chaque lancement d'app -> réaction immédiate.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        // Balayage périodique de filet de sécurité.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sweep()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        sweep()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appLaunched(_ note: Notification) {
        allowed = Set(allowedProvider()) // relit la whitelist (hot-reload)
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            sweep()
            return
        }
        enforce(app)
    }

    private func sweep() {
        allowed = Set(allowedProvider()) // relit la whitelist (hot-reload)
        for app in NSWorkspace.shared.runningApplications {
            enforce(app)
        }
    }

    /// Masque l'app non autorisée (au lieu de la fermer). On n'agit que sur les
    /// apps visibles : une fois masquée (`isHidden` == true) on ne la re-traite pas.
    private func enforce(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }   // uniquement apps GUI
        guard app != NSRunningApplication.current else { return } // pas nous-mêmes
        guard let bid = app.bundleIdentifier else { return }
        if allowed.contains(bid) || alwaysAllow.contains(bid) { return }
        guard !app.isHidden else { return } // déjà masquée -> rien à faire

        app.hide()
    }
}
