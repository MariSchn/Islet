import Foundation

struct HTTPRequest: Sendable, Equatable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    static func parse(_ data: Data) -> (request: HTTPRequest, consumed: Int)? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.endIndex - bodyStart >= length else { return nil }
        let body = data[bodyStart..<(bodyStart + length)]
        return (
            HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: Data(body)),
            bodyStart + length - data.startIndex
        )
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
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
