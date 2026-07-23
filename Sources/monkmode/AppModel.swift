import AppKit
import Combine

/// État global de MonkMode, observable par l'interface SwiftUI.
final class AppModel: ObservableObject {
    @Published var config: Config
    @Published var isActive = false
    @Published var remaining: TimeInterval = 0

    private let enforcer = AppEnforcer()
    private var proxy: SiteProxy?
    private var endDate: Date?
    private var tick: Timer?

    /// Whitelist figée au démarrage de la session. Pendant le focus, la liste
    /// EFFECTIVE = sessionAllowed ∩ config actuelle : on peut RETIRER une app
    /// (elle disparaît de la config -> masquée), mais pas en AJOUTER une
    /// nouvelle (absente de sessionAllowed -> reste bloquée). Anti-triche.
    private var sessionAllowed: Set<String> = []

    init() {
        config = Config.load()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateRemaining()
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    var isHardcoreLocked: Bool { isActive && config.hardcore && remaining > 0 }

    func saveConfig() { config.save() }

    /// Prolonge la session en cours. On ne peut QUE rajouter du temps.
    func addTime(minutes: Int) {
        guard isActive, minutes > 0, let end = endDate else { return }
        endDate = end.addingTimeInterval(TimeInterval(minutes * 60))
        updateRemaining()
    }

    func start(minutes: Int) {
        guard !isActive, minutes > 0 else { return }
        config.save() // persiste les réglages en cours
        endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        isActive = true
        sessionAllowed = Set(config.allowedApps) // figée pour toute la session
        updateRemaining()

        // Liste effective = figée ∩ config actuelle -> on peut retirer une app
        // pendant le focus (durcir), jamais en ajouter (assouplir).
        enforcer.start(allowedProvider: { [weak self] in
            guard let self else { return [] }
            return Array(self.sessionAllowed.intersection(Config.load().allowedApps))
        })

        // Le proxy bloque silencieusement les sites non autorisés (403 dans l'onglet).
        let p = SiteProxy(config: config, port: proxyPort)
        do {
            try p.start()
            proxy = p
            ProxySettings.enable(host: "127.0.0.1", port: proxyPort)
        } catch {
            NSLog("MonkMode: proxy non démarré (\(error)) — blocage sites inactif")
        }
    }

    @discardableResult
    func stop(force: Bool = false) -> Bool {
        guard isActive else { return true }
        if isHardcoreLocked && !force { return false }

        enforcer.stop()
        proxy?.stop(); proxy = nil
        ProxySettings.restore()

        isActive = false
        endDate = nil
        remaining = 0
        sessionAllowed = []
        return true
    }

    private func updateRemaining() {
        guard isActive, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            stop(force: true)
            NotificationCenter.default.post(name: .sessionEnded, object: nil)
        }
    }
}

extension Notification.Name {
    static let sessionEnded = Notification.Name("monkmode.sessionEnded")
}
