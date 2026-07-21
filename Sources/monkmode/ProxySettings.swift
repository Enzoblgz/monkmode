import Foundation

/// Active/désactive le proxy système via `networksetup`, avec sauvegarde de
/// l'état initial pour restauration exacte (même après un crash).
enum ProxySettings {

    struct Backup: Codable {
        struct ServiceState: Codable {
            var service: String
            var webEnabled: Bool
            var webServer: String
            var webPort: String
            var secureEnabled: Bool
            var secureServer: String
            var securePort: String
        }
        var services: [ServiceState]
    }

    static var backupURL: URL {
        Config.configDir.appendingPathComponent("proxy_backup.json")
    }

    // MARK: - API

    /// Sauvegarde l'état actuel puis pointe tous les services actifs vers host:port.
    static func enable(host: String, port: UInt16) {
        let services = activeServices()

        // Ne PAS écraser une sauvegarde existante : elle contient l'état
        // ORIGINAL de l'utilisateur (une session précédente ne s'est pas
        // restaurée). L'écraser enregistrerait notre propre proxy comme
        // « état normal » -> restauration cassée en boucle.
        if (try? Data(contentsOf: backupURL)) == nil {
            var states: [Backup.ServiceState] = []
            for s in services {
                // Si l'état courant pointe déjà vers NOTRE proxy (résidu d'une
                // session mal fermée), on le neutralise : on ne veut jamais
                // sauvegarder 127.0.0.1:9797 comme état à restaurer.
                states.append(sanitized(currentState(of: s), ourHost: host, ourPort: String(port)))
            }
            let backup = Backup(services: states)
            if let data = try? JSONEncoder().encode(backup) {
                try? data.write(to: backupURL)
            }
        }

        var cmds: [[String]] = []
        for s in services {
            cmds.append(["-setwebproxy", s, host, String(port)])
            cmds.append(["-setsecurewebproxy", s, host, String(port)])
            cmds.append(["-setwebproxystate", s, "on"])
            cmds.append(["-setsecurewebproxystate", s, "on"])
        }
        apply(cmds)
    }

    /// Restaure l'état sauvegardé (ou coupe le proxy à défaut de sauvegarde).
    static func restore() {
        guard let data = try? Data(contentsOf: backupURL),
              let backup = try? JSONDecoder().decode(Backup.self, from: data) else {
            // Pas de sauvegarde : on coupe simplement le proxy partout.
            var cmds: [[String]] = []
            for s in activeServices() {
                cmds.append(["-setwebproxystate", s, "off"])
                cmds.append(["-setsecurewebproxystate", s, "off"])
            }
            apply(cmds)
            return
        }

        var cmds: [[String]] = []
        for raw in backup.services {
            // Filet de sécurité : une sauvegarde qui pointe vers notre proxy
            // (127.0.0.1:proxyPort) est corrompue -> on la traite comme « off »
            // au lieu de rétablir un proxy mort qui couperait internet.
            let st = sanitized(raw, ourHost: "127.0.0.1", ourPort: String(proxyPort))
            if !st.webServer.isEmpty {
                cmds.append(["-setwebproxy", st.service, st.webServer, st.webPort])
            }
            cmds.append(["-setwebproxystate", st.service, st.webEnabled ? "on" : "off"])
            if !st.secureServer.isEmpty {
                cmds.append(["-setsecurewebproxy", st.service, st.secureServer, st.securePort])
            }
            cmds.append(["-setsecurewebproxystate", st.service, st.secureEnabled ? "on" : "off"])
        }
        apply(cmds)
        try? FileManager.default.removeItem(at: backupURL)
    }

    // MARK: - Lecture d'état

    private static func activeServices() -> [String] {
        let out = run("networksetup", ["-listallnetworkservices"])
        return out
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.contains("An asterisk") && !$0.hasPrefix("*") && !$0.isEmpty }
    }

    /// Neutralise un état qui pointe déjà vers notre propre proxy (résidu d'une
    /// session précédente mal restaurée) : traité comme « pas de proxy ».
    private static func sanitized(_ state: Backup.ServiceState, ourHost: String, ourPort: String) -> Backup.ServiceState {
        var s = state
        if s.webServer == ourHost && s.webPort == ourPort {
            s.webEnabled = false; s.webServer = ""; s.webPort = ""
        }
        if s.secureServer == ourHost && s.securePort == ourPort {
            s.secureEnabled = false; s.secureServer = ""; s.securePort = ""
        }
        return s
    }

    private static func currentState(of service: String) -> Backup.ServiceState {
        let web = parse(run("networksetup", ["-getwebproxy", service]))
        let secure = parse(run("networksetup", ["-getsecurewebproxy", service]))
        return Backup.ServiceState(
            service: service,
            webEnabled: web.enabled, webServer: web.server, webPort: web.port,
            secureEnabled: secure.enabled, secureServer: secure.server, securePort: secure.port
        )
    }

    private static func parse(_ out: String) -> (enabled: Bool, server: String, port: String) {
        var enabled = false, server = "", port = ""
        for line in out.split(separator: "\n") {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "Enabled": enabled = (kv[1] == "Yes")
            case "Server": server = kv[1]
            case "Port": port = kv[1]
            default: break
            }
        }
        return (enabled, server, port)
    }

    // MARK: - Exécution

    /// Exécute les commandes networksetup. En cas d'échec (droits admin requis),
    /// rejoue tout le lot via une élévation osascript unique.
    private static func apply(_ cmds: [[String]]) {
        var needsAdmin = false
        for args in cmds {
            let code = runStatus("/usr/sbin/networksetup", args)
            if code != 0 { needsAdmin = true; break }
        }
        guard needsAdmin else { return }

        let script = cmds.map { args in
            "/usr/sbin/networksetup " + args.map { "'\($0)'" }.joined(separator: " ")
        }.joined(separator: "; ")
        let osa = "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        _ = runStatus("/usr/bin/osascript", ["-e", osa])
    }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath.hasPrefix("/") ? launchPath : "/usr/sbin/\(launchPath)")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func runStatus(_ launchPath: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
