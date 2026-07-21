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
    /// Chemin d'une vidéo jouée plein écran quand un site est bloqué (optionnel).
    var blockVideoPath: String

    static let `default` = Config(
        allowedApps: [
            "com.apple.Safari"
        ],
        allowedDomains: [
            "wikipedia.org"
        ],
        presets: [25, 50, 90],
        hardcore: false,
        blockVideoPath: ""
    )

    init(allowedApps: [String], allowedDomains: [String], presets: [Int], hardcore: Bool, blockVideoPath: String) {
        self.allowedApps = allowedApps
        self.allowedDomains = allowedDomains
        self.presets = presets
        self.hardcore = hardcore
        self.blockVideoPath = blockVideoPath
    }

    // Décodage tolérant : toute clé absente prend la valeur par défaut.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        allowedApps = try c.decodeIfPresent([String].self, forKey: .allowedApps) ?? d.allowedApps
        allowedDomains = try c.decodeIfPresent([String].self, forKey: .allowedDomains) ?? d.allowedDomains
        presets = try c.decodeIfPresent([Int].self, forKey: .presets) ?? d.presets
        hardcore = try c.decodeIfPresent(Bool.self, forKey: .hardcore) ?? d.hardcore
        blockVideoPath = try c.decodeIfPresent(String.self, forKey: .blockVideoPath) ?? d.blockVideoPath
    }

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
