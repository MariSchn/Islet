import Foundation

struct HTTPRequest: Sendable, Equatable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    enum ParseResult: Sendable, Equatable {
        case incomplete
        case invalid
        case tooLarge(remainingBody: Int)
        case complete(HTTPRequest)
    }

    static let maxHeaderSize = 16 << 10

    static func parse(_ data: Data, maxBodySize: Int) -> ParseResult {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderSize ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
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
        let bodyStart = headerEnd.upperBound
        guard length <= maxBodySize else { return .tooLarge(remainingBody: length - (data.endIndex - bodyStart)) }
        guard data.endIndex - bodyStart >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]
        return .complete(HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: Data(body)))
    }

    var bearerToken: String? {
        guard let value = headers["authorization"], value.hasPrefix("Bearer ") else { return nil }
        return String(value.dropFirst("Bearer ".count))
    }
}

struct HTTPResponse: Sendable {
    var status: Int
    var body: Data

    static func json(_ status: Int = 200, _ body: String = "{}") -> HTTPResponse {
        HTTPResponse(status: status, body: Data(body.utf8))
    }

    var serialized: Data {
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
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
