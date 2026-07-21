import AppKit
import Combine

/// État global de MonkMode, observable par l'interface SwiftUI.
final class AppModel: ObservableObject {
    @Published var config: Config
    @Published var isActive = false
    @Published var remaining: TimeInterval = 0

    /// Fourni par l'AppDelegate : joue la vidéo de blocage (chemin) sur le thread principal.
    var onBlockVideo: ((String) -> Void)?

    private let enforcer = AppEnforcer()
    private var proxy: SiteProxy?
    private var endDate: Date?
    private var tick: Timer?

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

    func start(minutes: Int) {
        guard !isActive, minutes > 0 else { return }
        config.save() // persiste les réglages en cours
        endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        isActive = true
        updateRemaining()

        enforcer.onBlock = { [weak self] in
            guard let self else { return }
            let path = self.config.blockVideoPath
            guard !path.isEmpty else { return }
            DispatchQueue.main.async { self.onBlockVideo?(path) }
        }
        enforcer.start(allowedApps: config.allowedApps)

        let p = SiteProxy(config: config, port: proxyPort)
        p.onBlock = { [weak self] host in
            guard let self else { return }
            let path = self.config.blockVideoPath
            guard !path.isEmpty else { return }
            DispatchQueue.main.async { self.onBlockVideo?(path) }
        }
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
