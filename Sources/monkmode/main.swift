import AppKit

let proxyPort: UInt16 = 9797

// MARK: - Gestion de session

final class SessionManager {
    private(set) var isActive = false
    private(set) var endDate: Date?
    private var config = Config.load()

    private let enforcer = AppEnforcer()
    private var proxy: SiteProxy?
    private var endTimer: Timer?

    var remaining: TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSinceNow)
    }

    var presets: [Int] { config.presets }
    var isHardcoreLocked: Bool { isActive && config.hardcore && remaining > 0 }

    func reloadConfig() {
        config = Config.load()
    }

    func start(minutes: Int) {
        guard !isActive else { return }
        config = Config.load()
        isActive = true
        endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        enforcer.start(allowedApps: config.allowedApps)

        let p = SiteProxy(config: config, port: proxyPort)
        do {
            try p.start()
            proxy = p
            ProxySettings.enable(host: "127.0.0.1", port: proxyPort)
        } catch {
            NSLog("MonkMode: proxy non démarré (\(error)) — blocage sites inactif")
        }

        let t = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            self?.stop(force: true)
            NotificationCenter.default.post(name: .sessionEnded, object: nil)
        }
        RunLoop.main.add(t, forMode: .common)
        endTimer = t
    }

    /// Arrête la session. `force` ignore le verrou hardcore (fin de minuterie).
    @discardableResult
    func stop(force: Bool = false) -> Bool {
        guard isActive else { return true }
        if isHardcoreLocked && !force { return false }

        endTimer?.invalidate(); endTimer = nil
        enforcer.stop()
        proxy?.stop(); proxy = nil
        ProxySettings.restore()

        isActive = false
        endDate = nil
        return true
    }
}

extension Notification.Name {
    static let sessionEnded = Notification.Name("monkmode.sessionEnded")
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let session = SessionManager()
    private var tick: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nettoyage d'un éventuel proxy resté actif après un crash.
        if FileManager.default.fileExists(atPath: ProxySettings.backupURL.path) {
            ProxySettings.restore()
        }
        installSignalHandlers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🔓"

        NotificationCenter.default.addObserver(
            self, selector: #selector(onSessionEnded),
            name: .sessionEnded, object: nil
        )

        rebuildMenu()

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshTitle()
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if session.isActive {
            let stop = NSMenuItem(title: session.isHardcoreLocked ? "🔒 Verrouillé jusqu'à la fin"
                                                                   : "Arrêter la session",
                                  action: #selector(stopSession), keyEquivalent: "")
            stop.target = self
            stop.isEnabled = !session.isHardcoreLocked
            menu.addItem(stop)
        } else {
            for p in session.presets {
                let item = NSMenuItem(title: "Démarrer \(p) min", action: #selector(startSession(_:)), keyEquivalent: "")
                item.target = self
                item.tag = p
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let edit = NSMenuItem(title: "Modifier la configuration…", action: #selector(editConfig), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        let reload = NSMenuItem(title: "Recharger la configuration", action: #selector(reloadConfig), keyEquivalent: "")
        reload.target = self
        reload.isEnabled = !session.isActive
        menu.addItem(reload)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quitter MonkMode", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = !session.isHardcoreLocked
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func statusLine() -> String {
        guard session.isActive else { return "MonkMode — inactif" }
        return "Focus en cours — \(formatted(session.remaining)) restant"
    }

    private func refreshTitle() {
        if session.isActive {
            statusItem.button?.title = "🔒 \(formatted(session.remaining))"
        } else {
            statusItem.button?.title = "🔓"
        }
        // Met à jour la ligne d'état si le menu est ouvert.
        if let first = statusItem.menu?.items.first {
            first.title = statusLine()
        }
    }

    private func formatted(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Actions

    @objc private func startSession(_ sender: NSMenuItem) {
        session.start(minutes: sender.tag)
        rebuildMenu()
        refreshTitle()
    }

    @objc private func stopSession() {
        if session.stop() {
            rebuildMenu()
            refreshTitle()
        } else {
            NSSound.beep()
        }
    }

    @objc private func onSessionEnded() {
        rebuildMenu()
        refreshTitle()
        let n = NSUserNotification()
        n.title = "Session focus terminée"
        n.informativeText = "Tout est débloqué. Beau travail."
        NSUserNotificationCenter.default.deliver(n)
    }

    @objc private func editConfig() {
        _ = Config.load() // garantit l'existence du fichier
        NSWorkspace.shared.open(Config.configURL)
    }

    @objc private func reloadConfig() {
        session.reloadConfig()
        rebuildMenu()
    }

    @objc private func quit() {
        guard !session.isHardcoreLocked else { NSSound.beep(); return }
        session.stop(force: true)
        NSApp.terminate(nil)
    }

    // MARK: Nettoyage

    private func installSignalHandlers() {
        atexit { ProxySettings.restore() }
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig) { _ in
                ProxySettings.restore()
                exit(0)
            }
        }
    }
}

// Mode test : démarre uniquement le proxy (aucun blocage d'app, aucun proxy
// système). Sert à valider la logique de filtrage. Usage :
//   MONKMODE_PROXY_TEST="example.com" .build/debug/monkmode
if let allow = ProcessInfo.processInfo.environment["MONKMODE_PROXY_TEST"] {
    var cfg = Config.default
    cfg.allowedDomains = allow.split(separator: ",").map(String.init)
    let proxy = SiteProxy(config: cfg, port: proxyPort)
    try! proxy.start()
    FileHandle.standardError.write("proxy prêt sur \(proxyPort), autorisés: \(cfg.allowedDomains)\n".data(using: .utf8)!)
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
