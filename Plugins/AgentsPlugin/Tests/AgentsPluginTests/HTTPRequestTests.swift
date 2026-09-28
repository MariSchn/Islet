import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

struct HTTPRequestTests {
    @Test func parsesPostWithBodyAndWaitsForCompleteBody() {
        let head = "POST /hook HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nAuthorization: Bearer t\r\n\r\n"
        #expect(HTTPRequest.parse(Data((head + "ab").utf8), maxBodySize: 100) == .incomplete)
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nHo".utf8), maxBodySize: 100) == .incomplete)
        guard case .complete(let request) = HTTPRequest.parse(Data((head + "abcde").utf8), maxBodySize: 100) else {
            Issue.record("expected a complete request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/hook")
        #expect(request.bearerToken == "t")
        #expect(request.body == Data("abcde".utf8))
    }

    @Test func rejectsMalformedAndOversizedRequests() {
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nContent-Length: -3\r\n\r\n".utf8), maxBodySize: 100) == .invalid)
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nContent-Length: abc\r\n\r\n".utf8), maxBodySize: 100) == .invalid)
        #expect(HTTPRequest.parse(Data("GARBAGE\r\n\r\n".utf8), maxBodySize: 100) == .invalid)
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nno colon\r\n\r\n".utf8), maxBodySize: 100) == .invalid)
        #expect(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nContent-Length: 101\r\n\r\n".utf8), maxBodySize: 100) == .tooLarge(remainingBody: 101))
        #expect(HTTPRequest.parse(Data(repeating: UInt8(ascii: "a"), count: HTTPRequest.maxHeaderSize + 1), maxBodySize: 100) == .invalid)
    }

    @Test func serializesResponse() {
        let response = HTTPResponse.json(401, "{}")
        #expect(String(decoding: response.serialized, as: UTF8.self).hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(String(decoding: response.serialized, as: UTF8.self).hasSuffix("\r\n\r\n{}"))
    }
}
