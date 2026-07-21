import Foundation
import Network

/// Proxy HTTP/HTTPS local qui ne laisse passer que les domaines autorisés.
///
/// Le navigateur envoie ses requêtes ici (via le proxy système). En mode proxy,
/// les requêtes arrivent en « absolute-form » : le domaine cible est dans la
/// première ligne, aussi bien pour CONNECT (HTTPS) que pour GET/POST (HTTP).
final class SiteProxy {
    let port: UInt16
    private var config: Config
    private var listener: NWListener?
    /// Appelé (sur la file du proxy) avec l'hôte à chaque requête bloquée.
    var onBlock: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.enzo.monkmode.proxy", attributes: .concurrent)

    init(config: Config, port: UInt16) {
        self.config = config
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        l.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connexion entrante

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self, let data, !data.isEmpty, error == nil else {
                conn.cancel(); return
            }
            self.route(conn, initialData: data)
        }
    }

    private func route(_ client: NWConnection, initialData: Data) {
        guard let head = String(data: initialData, encoding: .utf8) ?? String(data: initialData, encoding: .isoLatin1),
              let firstLine = head.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
            client.cancel(); return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { client.cancel(); return }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])

        if method == "CONNECT" {
            // target = "host:port"
            let hp = target.split(separator: ":")
            let host = String(hp.first ?? "")
            let port = UInt16(hp.count > 1 ? String(hp[1]) : "443") ?? 443
            guard config.isDomainAllowed(host) else { return reject(client, host: host) }
            openUpstream(host: host, port: port) { upstream in
                guard let upstream else { client.cancel(); return }
                self.reply(client, "HTTP/1.1 200 Connection Established\r\n\r\n") {
                    self.forward(from: client, to: upstream)
                    self.forward(from: upstream, to: client)
                }
            }
        } else {
            // target = "http://host[:port]/path"
            guard let comps = URLComponents(string: target), let host = comps.host else {
                client.cancel(); return
            }
            let port = UInt16(comps.port ?? 80)
            guard config.isDomainAllowed(host) else { return reject(client, host: host) }
            openUpstream(host: host, port: port) { upstream in
                guard let upstream else { client.cancel(); return }
                // On rejoue la requête initiale telle quelle vers l'amont.
                upstream.send(content: initialData, completion: .contentProcessed { err in
                    if err != nil { client.cancel(); upstream.cancel(); return }
                    self.forward(from: client, to: upstream)
                    self.forward(from: upstream, to: client)
                })
            }
        }
    }

    // MARK: - Amont

    private func openUpstream(host: String, port: UInt16, completion: @escaping (NWConnection?) -> Void) {
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        var finished = false
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !finished { finished = true; completion(conn) }
            case .failed, .cancelled:
                if !finished { finished = true; completion(nil) }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    // MARK: - Tuyau bidirectionnel

    private func forward(from src: NWConnection, to dst: NWConnection) {
        src.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if error != nil { src.cancel(); dst.cancel(); return }
            if let data, !data.isEmpty {
                dst.send(content: data, completion: .contentProcessed { sErr in
                    if sErr != nil { src.cancel(); dst.cancel(); return }
                    if isComplete { src.cancel(); dst.cancel() }
                    else { self.forward(from: src, to: dst) }
                })
            } else if isComplete {
                src.cancel(); dst.cancel()
            } else {
                self.forward(from: src, to: dst)
            }
        }
    }

    // MARK: - Réponses au client

    private func reply(_ conn: NWConnection, _ text: String, then: (() -> Void)? = nil) {
        conn.send(content: text.data(using: .utf8), completion: .contentProcessed { _ in then?() })
    }

    private func reject(_ conn: NWConnection, host: String) {
        onBlock?(host)
        let body = "MonkMode a bloqué \(host)."
        let resp = """
        HTTP/1.1 403 Forbidden\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}
