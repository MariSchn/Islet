import Foundation
import Testing
@testable import IsletCore

struct HTTPRequestTests {
    @Test func parsesTheHeadAndLocatesTheBody() {
        let head = "POST /hook HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nAuthorization: Bearer t\r\n\r\n"
        #expect(HTTPRequest.parseHead(Data("POST /hook HTTP/1.1\r\nHo".utf8)) == .incomplete)
        guard case .complete(let request, let length, let bodyStart) = HTTPRequest.parseHead(Data((head + "ab").utf8)) else {
            Issue.record("expected a complete head")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/hook")
        #expect(request.bearerToken == "t")
        #expect(request.body.isEmpty)
        #expect(length == 5)
        #expect(bodyStart == head.utf8.count)
    }

    @Test func rejectsMalformedHeads() {
        #expect(HTTPRequest.parseHead(Data("POST /hook HTTP/1.1\r\nContent-Length: -3\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequest.parseHead(Data("POST /hook HTTP/1.1\r\nContent-Length: abc\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequest.parseHead(Data("GARBAGE\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequest.parseHead(Data("POST /hook HTTP/1.1\r\nno colon\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequest.parseHead(Data(repeating: UInt8(ascii: "a"), count: HTTPRequest.maxHeaderSize + 1)) == .invalid)
    }

    @Test func comparesBearerTokens() {
        let request = HTTPRequest(method: "GET", path: "/", headers: ["authorization": "Bearer secret"])
        #expect(request.hasBearerToken("secret"))
        #expect(!request.hasBearerToken("secreT"))
        #expect(!request.hasBearerToken("secret2"))
        #expect(!HTTPRequest(method: "GET", path: "/").hasBearerToken("secret"))
    }

    @Test func serializesResponse() {
        let response = HTTPResponse.json(401, "{}")
        #expect(String(decoding: response.serialized, as: UTF8.self).hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(String(decoding: response.serialized, as: UTF8.self).hasSuffix("\r\n\r\n{}"))
    }
}
