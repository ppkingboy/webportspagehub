import Foundation
import Network

enum StaticHTTPServerError: LocalizedError {
    case invalidPort
    case listenerFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "端口号必须介于 1 到 65535 之间。"
        case .listenerFailed(let message):
            return "无法启动服务：\(message)"
        }
    }
}

final class StaticHTTPServer {
    var onStateChange: ((Bool, String?) -> Void)?

    private let rootURL: URL
    private let library: PageLibrary
    private let queue = DispatchQueue(label: "com.anhuajinhe.staticpages.http")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(rootURL: URL, library: PageLibrary) {
        self.rootURL = rootURL.standardizedFileURL
        self.library = library
    }

    func start(port: UInt16) throws {
        guard port > 0, let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw StaticHTTPServerError.invalidPort
        }

        stop()

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: networkPort)
        } catch {
            throw StaticHTTPServerError.listenerFailed(error.localizedDescription)
        }

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else {
                return
            }

            switch state {
            case .ready:
                self.onStateChange?(true, nil)
            case .failed(let error):
                self.listener = nil
                self.onStateChange?(false, error.localizedDescription)
            case .cancelled:
                if self.listener === listener {
                    self.listener = nil
                    self.onStateChange?(false, nil)
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        connections[identifier] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else {
                return
            }

            if case .failed = state {
                self.connections.removeValue(forKey: ObjectIdentifier(connection))
            }
        }

        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else {
                return
            }

            var requestData = buffer
            if let data {
                requestData.append(data)
            }

            if requestData.count > 128 * 1024 {
                self.sendStatus(413, reason: "Payload Too Large", on: connection)
                return
            }

            if let headerRange = requestData.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = requestData[..<headerRange.lowerBound]
                self.processRequest(Data(headerData), on: connection)
                return
            }

            if isComplete || error != nil {
                self.sendStatus(400, reason: "Bad Request", on: connection)
                return
            }

            self.receiveRequest(on: connection, buffer: requestData)
        }
    }

    private func processRequest(_ headerData: Data, on connection: NWConnection) {
        guard let header = String(data: headerData, encoding: .utf8),
              let requestLine = header.components(separatedBy: "\r\n").first else {
            sendStatus(400, reason: "Bad Request", on: connection)
            return
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            sendStatus(400, reason: "Bad Request", on: connection)
            return
        }

        let method = String(parts[0]).uppercased()
        let target = String(parts[1])

        guard method == "GET" || method == "HEAD" else {
            sendStatus(405, reason: "Method Not Allowed", on: connection)
            return
        }

        let path = decodedPath(from: target)

        if path == "/__pages.json" {
            sendPagesJSON(on: connection, includeBody: method != "HEAD")
            return
        }

        let fileURL = resolvedFileURL(for: path)
        guard isInsideRoot(fileURL) else {
            sendStatus(403, reason: "Forbidden", on: connection)
            return
        }

        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            sendStatus(404, reason: "Not Found", on: connection)
            return
        }

        send(
            status: 200,
            reason: "OK",
            contentType: mimeType(for: fileURL),
            body: data,
            includeBody: method != "HEAD",
            on: connection
        )
    }

    private func decodedPath(from target: String) -> String {
        let rawPath: String

        if let components = URLComponents(string: target), !components.path.isEmpty {
            rawPath = components.path
        } else if let components = URLComponents(string: "http://localhost\(target)") {
            rawPath = components.path
        } else {
            rawPath = "/"
        }

        return rawPath.removingPercentEncoding ?? rawPath
    }

    private func resolvedFileURL(for requestPath: String) -> URL {
        let relativePath = requestPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var fileURL = rootURL.appendingPathComponent(relativePath)

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            fileURL.appendPathComponent("index.html")
        }

        return fileURL.standardizedFileURL
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.path
        return url.path == rootPath || url.path.hasPrefix(rootPath + "/")
    }

    private func sendPagesJSON(on connection: NWConnection, includeBody: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(library.scanPages()) else {
            sendStatus(500, reason: "Internal Server Error", on: connection)
            return
        }

        send(
            status: 200,
            reason: "OK",
            contentType: "application/json; charset=utf-8",
            body: data,
            includeBody: includeBody,
            on: connection
        )
    }

    private func sendStatus(_ status: Int, reason: String, on connection: NWConnection) {
        let html = "<!doctype html><meta charset=\"utf-8\"><title>\(status)</title><h1>\(status) \(reason)</h1>"
        send(
            status: status,
            reason: reason,
            contentType: "text/html; charset=utf-8",
            body: Data(html.utf8),
            includeBody: true,
            on: connection
        )
    }

    private func send(
        status: Int,
        reason: String,
        contentType: String,
        body: Data,
        includeBody: Bool,
        on connection: NWConnection
    ) {
        var headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-cache",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        if includeBody {
            response.append(body)
        }

        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.finish(connection)
        })
        headers.removeAll()
    }

    private func finish(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private func mimeType(for url: URL) -> String {
        let lowercasedName = url.lastPathComponent.lowercased()

        if lowercasedName.contains(".html") {
            return "text/html; charset=utf-8"
        }
        if lowercasedName.contains(".css") {
            return "text/css; charset=utf-8"
        }
        if lowercasedName.contains(".js") {
            return "application/javascript; charset=utf-8"
        }

        switch url.pathExtension.lowercased() {
        case "json":
            return "application/json; charset=utf-8"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "ico":
            return "image/x-icon"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        default:
            return "application/octet-stream"
        }
    }
}
