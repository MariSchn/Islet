import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    enum HeadParseResult: Sendable, Equatable {
        case incomplete
        case invalid
        case complete(HTTPRequest, contentLength: Int, bodyStart: Int)
    }

    static let maxHeaderSize = 16 << 10

    static func parseHead(_ data: Data) -> HeadParseResult {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderSize ? .invalid : .incomplete
        }
        guard headerEnd.lowerBound - data.startIndex <= maxHeaderSize,
              let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8)
        else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length: Int
        if let value = headers["content-length"] {
            guard let parsed = Int(value), parsed >= 0 else { return .invalid }
            length = parsed
        } else {
            length = 0
        }
        let request = HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers)
        return .complete(request, contentLength: length, bodyStart: headerEnd.upperBound - data.startIndex)
    }

    public var bearerToken: String? {
        guard let value = headers["authorization"], value.hasPrefix("Bearer ") else { return nil }
        return String(value.dropFirst("Bearer ".count))
    }

    public func hasBearerToken(_ token: String) -> Bool {
        guard let presented = bearerToken?.utf8, presented.count == token.utf8.count else { return false }
        return zip(presented, token.utf8).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data

    public init(status: Int, contentType: String, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static func json(_ status: Int = 200, _ body: String = "{}") -> HTTPResponse {
        HTTPResponse(status: status, contentType: "application/json", body: Data(body.utf8))
    }

    public static func text(_ body: String) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", body: Data(body.utf8))
    }

    public var serialized: Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
