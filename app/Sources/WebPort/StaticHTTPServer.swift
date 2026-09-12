import Foundation
import Network

enum ServerBinding: String, CaseIterable {
    case localhost
    case lan
    case all

    var title: String {
        switch self {
        case .localhost:
            return "仅本机"
        case .lan:
            return "指定网卡"
        case .all:
            return "全部网络"
        }
    }
}

enum StaticHTTPServerError: LocalizedError {
    case invalidPort
    case invalidAddress
    case listenerFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "端口号必须介于 1 到 65535 之间。"
        case .invalidAddress:
            return "所选网络地址无效。"
        case .listenerFailed(let message):
            return "无法启动服务：\(message)"
        }
    }
}

struct AccessLogEntry {
    let remoteAddress: String
    let path: String
    let status: Int
    let date: Date
}

final class StaticHTTPServer {
    var onStateChange: ((Bool, String?) -> Void)?
    var onAccess: ((AccessLogEntry) -> Void)?

    private let rootURL: URL
    private let library: PageLibrary
    private let queue = DispatchQueue(label: "com.webport.staticpages.http")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var fileSenders: [ObjectIdentifier: FileSender] = [:]
    private var accessCode = ""

    init(rootURL: URL, library: PageLibrary) {
        self.rootURL = rootURL.standardizedFileURL
        self.library = library
    }

    func start(
        port: UInt16,
        binding: ServerBinding,
        selectedAddress: String?,
        accessCode: String?
    ) throws {
        guard port > 0, let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw StaticHTTPServerError.invalidPort
        }

        stop()
        self.accessCode = accessCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let parameters = NWParameters.tcp

        switch binding {
        case .localhost:
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(.loopback),
                port: networkPort
            )
        case .lan:
            guard let selectedAddress,
                  let ipv4Address = IPv4Address(selectedAddress) else {
                throw StaticHTTPServerError.invalidAddress
            }

            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(ipv4Address),
                port: networkPort
            )
        case .all:
            break
        }

        let listener: NWListener
        do {
            if binding == .all {
                listener = try NWListener(using: parameters, on: networkPort)
            } else {
                listener = try NWListener(using: parameters)
            }
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

            self.fileSenders.values.forEach { $0.cancel() }
            self.fileSenders.removeAll()
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
                self.finish(connection)
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
        let headers = parsedHeaders(from: header)

        guard method == "GET" || method == "HEAD" else {
            sendStatus(405, reason: "Method Not Allowed", on: connection)
            return
        }

        guard isAuthorized(headers: headers, connection: connection) else {
            return
        }

        let path = decodedPath(from: target)
        onAccess?(
            AccessLogEntry(
                remoteAddress: remoteAddress(for: connection),
                path: path,
                status: 200,
                date: Date()
            )
        )

        if path == "/__pages.json" {
            sendPagesJSON(on: connection, includeBody: method != "HEAD")
            return
        }

        let fileURL = resolvedFileURL(for: path)
        guard isInsideRoot(fileURL) else {
            sendStatus(403, reason: "Forbidden", on: connection)
            return
        }

        sendFile(
            at: fileURL,
            requestHeaders: headers,
            includeBody: method != "HEAD",
            on: connection
        )
    }

    private func parsedHeaders(from request: String) -> [String: String] {
        var headers: [String: String] = [:]

        for line in request.components(separatedBy: "\r\n").dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }

            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return headers
    }

    private func isAuthorized(
        headers: [String: String],
        connection: NWConnection
    ) -> Bool {
        guard !accessCode.isEmpty else {
            return true
        }

        let credentials = Data("guest:\(accessCode)".utf8).base64EncodedString()
        let expectedValue = "Basic \(credentials)"

        guard headers["authorization"] == expectedValue else {
            send(
                status: 401,
                reason: "Unauthorized",
                contentType: "text/plain; charset=utf-8",
                body: Data("Access code required.\n".utf8),
                includeBody: true,
                extraHeaders: ["WWW-Authenticate": "Basic realm=\"Static Pages\""],
                on: connection
            )
            return false
        }

        return true
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
            extraHeaders: ["Cache-Control": "no-store"],
            on: connection
        )
    }

    private func sendFile(
        at url: URL,
        requestHeaders: [String: String],
        includeBody: Bool,
        on connection: NWConnection
    ) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSizeNumber = attributes[.size] as? NSNumber else {
            sendStatus(404, reason: "Not Found", on: connection)
            return
        }

        let fileSize = fileSizeNumber.uint64Value
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()
        let etag = makeETag(size: fileSize, modificationDate: modificationDate)
        let lastModified = httpDate(modificationDate)

        if requestHeaders["if-none-match"] == etag
            || isNotModified(requestHeaders["if-modified-since"], modificationDate: modificationDate) {
            sendResponseHeaders(
                status: 304,
                reason: "Not Modified",
                headers: [
                    "ETag": etag,
                    "Last-Modified": lastModified,
                    "Accept-Ranges": "bytes",
                    "Cache-Control": "public, max-age=0, must-revalidate"
                ],
                contentLength: nil,
                on: connection,
                completion: { [weak self] in self?.finish(connection) }
            )
            return
        }

        let byteRange: ClosedRange<UInt64>?
        let status: Int
        let reason: String
        let contentLength: UInt64

        if let rangeHeader = requestHeaders["range"] {
            guard let parsedRange = parseRange(rangeHeader, fileSize: fileSize) else {
                sendResponseHeaders(
                    status: 416,
                    reason: "Range Not Satisfiable",
                    headers: [
                        "Content-Range": "bytes */\(fileSize)",
                        "Accept-Ranges": "bytes"
                    ],
                    contentLength: 0,
                    on: connection,
                    completion: { [weak self] in self?.finish(connection) }
                )
                return
            }

            byteRange = parsedRange
            status = 206
            reason = "Partial Content"
            contentLength = parsedRange.upperBound - parsedRange.lowerBound + 1
        } else {
            byteRange = nil
            status = 200
            reason = "OK"
            contentLength = fileSize
        }

        var responseHeaders = [
            "Content-Type": mimeType(for: url),
            "ETag": etag,
            "Last-Modified": lastModified,
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=0, must-revalidate"
        ]

        if let byteRange {
            responseHeaders["Content-Range"] =
                "bytes \(byteRange.lowerBound)-\(byteRange.upperBound)/\(fileSize)"
        }

        sendResponseHeaders(
            status: status,
            reason: reason,
            headers: responseHeaders,
            contentLength: contentLength,
            on: connection
        ) { [weak self] in
            guard let self else {
                return
            }

            guard includeBody, contentLength > 0 else {
                self.finish(connection)
                return
            }

            do {
                let fileHandle = try FileHandle(forReadingFrom: url)
                let start = byteRange?.lowerBound ?? 0
                if start > 0 {
                    try fileHandle.seek(toOffset: start)
                }

                let sender = FileSender(
                    connection: connection,
                    fileHandle: fileHandle,
                    remainingBytes: contentLength,
                    server: self
                )
                self.fileSenders[ObjectIdentifier(connection)] = sender
                sender.start()
            } catch {
                self.finish(connection)
            }
        }
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
        extraHeaders: [String: String] = [:],
        on connection: NWConnection
    ) {
        var headers = [
            "Content-Type": contentType,
            "Cache-Control": "no-cache"
        ]
        headers.merge(extraHeaders) { _, newValue in newValue }

        sendResponseHeaders(
            status: status,
            reason: reason,
            headers: headers,
            contentLength: UInt64(body.count),
            on: connection
        ) { [weak self] in
            guard let self else {
                return
            }

            guard includeBody, !body.isEmpty else {
                self.finish(connection)
                return
            }

            connection.send(content: body, completion: .contentProcessed { _ in
                self.finish(connection)
            })
        }
    }

    private func sendResponseHeaders(
        status: Int,
        reason: String,
        headers: [String: String],
        contentLength: UInt64?,
        on connection: NWConnection,
        completion: @escaping () -> Void
    ) {
        var lines = [
            "HTTP/1.1 \(status) \(reason)",
            "Connection: close"
        ]

        if let contentLength {
            lines.append("Content-Length: \(contentLength)")
        }

        for key in headers.keys.sorted() {
            if let value = headers[key] {
                lines.append("\(key): \(value)")
            }
        }

        lines.append("")
        lines.append("")

        connection.send(
            content: Data(lines.joined(separator: "\r\n").utf8),
            completion: .contentProcessed { error in
                if error == nil {
                    completion()
                } else {
                    connection.cancel()
                }
            }
        )
    }

    fileprivate func finish(_ connection: NWConnection) {
        if let sender = fileSenders.removeValue(forKey: ObjectIdentifier(connection)) {
            sender.cancel()
        }
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private func makeETag(size: UInt64, modificationDate: Date) -> String {
        "\"\(size)-\(Int(modificationDate.timeIntervalSince1970))\""
    }

    private func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private func isNotModified(_ value: String?, modificationDate: Date) -> Bool {
        guard let value else {
            return false
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        guard let date = formatter.date(from: value) else {
            return false
        }

        return modificationDate.timeIntervalSince1970 <= date.timeIntervalSince1970
    }

    private func parseRange(_ value: String, fileSize: UInt64) -> ClosedRange<UInt64>? {
        guard fileSize > 0,
              value.lowercased().hasPrefix("bytes=") else {
            return nil
        }

        let rangeValue = value.dropFirst("bytes=".count)
        guard !rangeValue.contains(",") else {
            return nil
        }

        let parts = rangeValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }

        if parts[0].isEmpty {
            guard let suffixLength = UInt64(parts[1]), suffixLength > 0 else {
                return nil
            }

            let start = fileSize > suffixLength ? fileSize - suffixLength : 0
            return start...(fileSize - 1)
        }

        guard let start = UInt64(parts[0]), start < fileSize else {
            return nil
        }

        let requestedEnd = UInt64(parts[1]) ?? (fileSize - 1)
        let end = min(requestedEnd, fileSize - 1)
        guard start <= end else {
            return nil
        }

        return start...end
    }

    private func remoteAddress(for connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return String(describing: connection.endpoint)
        }
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
        case "xml":
            return "application/xml; charset=utf-8"
        case "txt":
            return "text/plain; charset=utf-8"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "ico":
            return "image/x-icon"
        case "pdf":
            return "application/pdf"
        case "mp4":
            return "video/mp4"
        case "webm":
            return "video/webm"
        case "mp3":
            return "audio/mpeg"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        case "wasm":
            return "application/wasm"
        default:
            return "application/octet-stream"
        }
    }
}

private final class FileSender {
    private static let chunkSize = 256 * 1024

    private let connection: NWConnection
    private let fileHandle: FileHandle
    private var remainingBytes: UInt64
    private weak var server: StaticHTTPServer?

    init(
        connection: NWConnection,
        fileHandle: FileHandle,
        remainingBytes: UInt64,
        server: StaticHTTPServer
    ) {
        self.connection = connection
        self.fileHandle = fileHandle
        self.remainingBytes = remainingBytes
        self.server = server
    }

    func start() {
        sendNextChunk()
    }

    func cancel() {
        try? fileHandle.close()
    }

    private func sendNextChunk() {
        guard remainingBytes > 0 else {
            try? fileHandle.close()
            server?.finish(connection)
            return
        }

        let requestedBytes = Int(min(UInt64(Self.chunkSize), remainingBytes))

        do {
            guard let data = try fileHandle.read(upToCount: requestedBytes),
                  !data.isEmpty else {
                throw CocoaError(.fileReadUnknown)
            }

            let isFinalChunk = UInt64(data.count) >= remainingBytes
            connection.send(
                content: data,
                isComplete: isFinalChunk,
                completion: .contentProcessed { [weak self] error in
                    guard let self else {
                        return
                    }

                    if error != nil {
                        try? self.fileHandle.close()
                        self.server?.finish(self.connection)
                        return
                    }

                    self.remainingBytes -= UInt64(data.count)
                    if self.remainingBytes == 0 {
                        try? self.fileHandle.close()
                        self.server?.finish(self.connection)
                    } else {
                        self.sendNextChunk()
                    }
                }
            )
        } catch {
            try? fileHandle.close()
            server?.finish(connection)
        }
    }
}
