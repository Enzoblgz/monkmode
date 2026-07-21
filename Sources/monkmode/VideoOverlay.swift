import AppKit
import AVKit

/// Joue une vidéo plein écran par-dessus tout (rappel de motivation au blocage).
/// Se ferme à la fin de la vidéo, ou sur Échap / clic.
final class VideoOverlay: NSObject {
    private var window: NSWindow?
    private var player: AVPlayer?
    private var lastShown = Date.distantPast

    /// Affiche la vidéo. Ignoré si déjà en cours ou joué il y a moins de 5 s.
    func play(path: String) {
        guard window == nil else { return }
        guard Date().timeIntervalSince(lastShown) > 5 else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("MonkMode: vidéo de blocage introuvable: \(path)")
            NSSound.beep()
            return
        }
        lastShown = Date()

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let win = KeyableWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = .screenSaver
        win.isOpaque = true
        win.backgroundColor = .black
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.setFrame(screen.frame, display: true)

        let p = AVPlayer(url: url)
        let pv = AVPlayerView(frame: screen.frame)
        pv.player = p
        pv.controlsStyle = .none
        pv.videoGravity = .resizeAspect
        pv.autoresizingMask = [.width, .height]

        let container = NSView(frame: screen.frame)
        container.autoresizingMask = [.width, .height]
        container.addSubview(pv)

        // Le capteur de clic/Échap est PLACÉ AU-DESSUS de l'AVPlayerView,
        // sinon le player capte le clic et la vidéo ne se ferme jamais.
        let catcher = ClickCatcher(target: self, action: #selector(dismiss))
        catcher.frame = screen.frame
        catcher.autoresizingMask = [.width, .height]
        container.addSubview(catcher)

        win.contentView = container

        self.window = win
        self.player = p

        NotificationCenter.default.addObserver(
            self, selector: #selector(dismiss),
            name: .AVPlayerItemDidPlayToEndTime, object: p.currentItem
        )

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(catcher) // pour recevoir l'Échap
        p.play()
    }

    /// Fenêtre borderless capable de devenir « key » -> reçoit les touches (Échap).
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    @objc func dismiss() {
        player?.pause()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        window?.orderOut(nil)
        window = nil
        player = nil
    }

    /// Vue qui capte Échap et le clic pour fermer.
    private final class ClickCatcher: NSView {
        weak var target: AnyObject?
        let action: Selector
        init(target: AnyObject, action: Selector) {
            self.target = target
            self.action = action
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) {
            _ = target?.perform(action)
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { _ = target?.perform(action) } // Échap
        }
    }
}
