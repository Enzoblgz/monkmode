import AppKit
import SwiftUI

let proxyPort: UInt16 = 9797

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem!
    private var tick: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nettoyage d'un proxy resté actif après un crash.
        if FileManager.default.fileExists(atPath: ProxySettings.backupURL.path) {
            ProxySettings.restore()
        }
        installSignalHandlers()

        setupWindow()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(onSessionEnded),
            name: .sessionEnded, object: nil
        )

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    // MARK: Fenêtre

    private func setupWindow() {
        let host = NSHostingController(rootView: ConfigView(model: model))
        let win = NSWindow(contentViewController: host)
        win.title = "MonkMode"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 480, height: 600))
        win.center()
        win.isReleasedWhenClosed = false
        window = win
        showWindow()
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // Clic sur l'icône du Dock -> rouvre la fenêtre.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // reste actif en tâche de fond (menu bar)
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(active: false)
        rebuildMenu()
    }

    private func setIcon(active: Bool) {
        guard let button = statusItem.button else { return }
        let name = active ? "lock.fill" : "lock.open"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "MonkMode")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Ouvrir MonkMode", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        if model.isActive {
            let line = NSMenuItem(title: "Focus — \(formatted(model.remaining)) restant", action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
            let stop = NSMenuItem(title: model.isHardcoreLocked ? "🔒 Verrouillé jusqu'à la fin" : "Arrêter la session",
                                  action: #selector(stopSession), keyEquivalent: "")
            stop.target = self
            stop.isEnabled = !model.isHardcoreLocked
            menu.addItem(stop)
        } else {
            for p in model.config.presets {
                let item = NSMenuItem(title: "Démarrer \(p) min", action: #selector(startPreset(_:)), keyEquivalent: "")
                item.target = self
                item.tag = p
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter MonkMode", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = !model.isHardcoreLocked
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func refreshStatus() {
        setIcon(active: model.isActive)
        statusItem.button?.title = model.isActive ? " \(formatted(model.remaining))" : ""
        rebuildMenu()
    }

    private func formatted(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Actions

    @objc private func openWindow() { showWindow() }

    @objc private func startPreset(_ sender: NSMenuItem) {
        model.start(minutes: sender.tag)
        refreshStatus()
    }

    @objc private func stopSession() {
        if !model.stop() { NSSound.beep(); return }
        refreshStatus()
    }

    @objc private func onSessionEnded() {
        refreshStatus()
        let n = NSUserNotification()
        n.title = "Session MonkMode terminée"
        n.informativeText = "Tout est débloqué. Beau travail."
        NSUserNotificationCenter.default.deliver(n)
    }

    @objc private func quit() {
        guard !model.isHardcoreLocked else { NSSound.beep(); return }
        model.stop(force: true)
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.isHardcoreLocked ? .terminateCancel : .terminateNow
    }

    // MARK: Nettoyage proxy

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
// système). Usage : MONKMODE_PROXY_TEST="example.com" .build/debug/monkmode
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
app.setActivationPolicy(.regular) // icône dans le Dock + fenêtre
app.run()
