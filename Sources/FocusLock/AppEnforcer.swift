import AppKit

/// Tue en continu toute application GUI non autorisée.
///
/// Sécurité : ne touche qu'aux apps « regular » (présence dans le Dock).
/// Les démons/agents système (.accessory, .prohibited) ne sont jamais tués,
/// ce qui évite de casser macOS. Finder et FocusLock lui-même sont épargnés.
final class AppEnforcer {
    private var timer: Timer?
    private var allowed: Set<String> = []

    /// Bundle IDs toujours épargnés en plus de la whitelist utilisateur.
    private let alwaysAllow: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.WindowManager"
    ]

    func start(allowedApps: [String]) {
        allowed = Set(allowedApps)
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
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            sweep()
            return
        }
        kill(app)
    }

    private func sweep() {
        for app in NSWorkspace.shared.runningApplications {
            kill(app)
        }
    }

    private func kill(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }   // uniquement apps GUI
        guard app != NSRunningApplication.current else { return } // pas nous-mêmes
        guard let bid = app.bundleIdentifier else { return }
        if allowed.contains(bid) || alwaysAllow.contains(bid) { return }

        if !app.terminate() {
            app.forceTerminate()
        }
    }
}
