import Foundation
import IsletCore
import Testing
@testable import ScriptsPlugin

struct ScriptRequestTests {
    private func activity(_ json: String) throws -> ScriptActivityRequest {
        try ScriptActivityRequest.decode(Data(json.utf8))
    }

    @Test func decodesMinimalAndFullActivities() throws {
        let minimal = try activity(#"{"id":"a","text":"Hi"}"#)
        #expect(minimal == ScriptActivityRequest(id: "a", text: "Hi", symbol: nil, progress: nil, priority: .info, ttl: 600))
        let full = try activity(#"{"id":"b.c_d-1","text":"Go","symbol":"star.fill","progress":0.5,"priority":"urgent","ttl":86400}"#)
        #expect(full == ScriptActivityRequest(id: "b.c_d-1", text: "Go", symbol: "star.fill", progress: 0.5, priority: .urgent, ttl: 86400))
        #expect(try activity(#"{"id":"a","text":"x","progress":0}"#).progress == 0)
        #expect(try activity(#"{"id":"a","text":"x","progress":1}"#).progress == 1)
    }

    @Test func rejectsInvalidActivities() {
        let long = String(repeating: "a", count: 65)
        let longText = String(repeating: "t", count: 201)
        let bodies = [
            "not json", "[]", "{}",
            #"{"text":"x"}"#, #"{"id":"","text":"x"}"#, #"{"id":"\#(long)","text":"x"}"#, #"{"id":"a b","text":"x"}"#, #"{"id":"a/b","text":"x"}"#, #"{"id":1,"text":"x"}"#,
            #"{"id":"a"}"#, #"{"id":"a","text":""}"#, #"{"id":"a","text":"\#(longText)"}"#, #"{"id":"a","text":5}"#,
            #"{"id":"a","text":"x","symbol":3}"#,
            #"{"id":"a","text":"x","progress":1.1}"#, #"{"id":"a","text":"x","progress":-0.1}"#, #"{"id":"a","text":"x","progress":"0.5"}"#, #"{"id":"a","text":"x","progress":true}"#,
            #"{"id":"a","text":"x","priority":"high"}"#, #"{"id":"a","text":"x","priority":1}"#,
            #"{"id":"a","text":"x","ttl":0}"#, #"{"id":"a","text":"x","ttl":-1}"#, #"{"id":"a","text":"x","ttl":86401}"#, #"{"id":"a","text":"x","ttl":"5"}"#,
        ]
        for body in bodies {
            #expect(throws: ScriptRequestError.self, "\(body)") { try activity(body) }
        }
    }

    @Test func acceptsTheLengthLimits() throws {
        let id = String(repeating: "a", count: 64)
        let text = String(repeating: "t", count: 200)
        #expect(try activity(#"{"id":"\#(id)","text":"\#(text)"}"#).text == text)
    }

    @Test func decodesAnnouncements() throws {
        let request = try ScriptAnnounceRequest.decode(Data(#"{"text":"Done","symbol":"checkmark","priority":"attention"}"#.utf8))
        #expect(request == ScriptAnnounceRequest(text: "Done", symbol: "checkmark", priority: .attention))
        #expect(try ScriptAnnounceRequest.decode(Data(#"{"text":"Done"}"#.utf8)).priority == .info)
        #expect(throws: ScriptRequestError.self) { try ScriptAnnounceRequest.decode(Data("{}".utf8)) }
        #expect(throws: ScriptRequestError.self) { try ScriptAnnounceRequest.decode(Data(#"{"text":"x","priority":"nope"}"#.utf8)) }
    }

    @Test func unknownSymbolsFallBack() {
        #expect(ScriptSymbol.resolved("star.fill") == "star.fill")
        #expect(ScriptSymbol.resolved("definitely.not.a.symbol") == "bolt.fill")
        #expect(ScriptSymbol.resolved(nil) == "bolt.fill")
    }
}
