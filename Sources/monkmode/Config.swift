import Foundation

/// Configuration lue depuis ~/.monkmode/config.json
struct Config: Codable {
    /// Bundle identifiers des apps autorisées (ex: "com.apple.Safari").
    var allowedApps: [String]
    /// Domaines autorisés (ex: "moodle.univ.fr"). Les sous-domaines sont autorisés.
    var allowedDomains: [String]
    /// Durées proposées dans le menu, en minutes.
    var presets: [Int]
    /// Si true, une session ne peut pas être arrêtée avant la fin.
    var hardcore: Bool

    static let `default` = Config(
        allowedApps: [
            "com.apple.Safari"
        ],
        allowedDomains: [
            "wikipedia.org"
        ],
        presets: [25, 50, 90],
        hardcore: false
    )

    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".monkmode", isDirectory: true)
    }

    static var configURL: URL {
        configDir.appendingPathComponent("config.json")
    }

    /// Charge la config, en créant le fichier par défaut si absent.
    static func load() -> Config {
        let fm = FileManager.default
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: configURL) else {
            let cfg = Config.default
            cfg.save()
            return cfg
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            NSLog("MonkMode: config illisible (\(error)) — valeurs par défaut utilisées")
            return Config.default
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return }
        try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        try? data.write(to: Config.configURL)
    }

    /// Un hôte est autorisé s'il correspond exactement ou est un sous-domaine
    /// d'un domaine autorisé.
    func isDomainAllowed(_ host: String) -> Bool {
        let h = host.lowercased()
        for d in allowedDomains {
            let dd = d.lowercased()
            if h == dd || h.hasSuffix("." + dd) {
                return true
            }
        }
        return false
    }
}
