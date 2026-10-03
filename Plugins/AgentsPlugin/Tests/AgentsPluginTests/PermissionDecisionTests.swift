import Foundation
import Testing
@testable import AgentsPlugin

struct PermissionDecisionTests {
    @Test func allowAlwaysEchoesTheSuggestion() throws {
        let suggestion = Self.suggestion(destination: "localSettings", rules: [("Bash", "rm -rf node_modules")])
        let request = try #require(PendingRequest(toolName: "Bash", toolInput: .object(["command": .string("rm -rf node_modules")]), permissionSuggestions: [suggestion]))
        let reply = PermissionDecision.allowAlways.reply(for: request)
        #expect(reply.body == #"{"hookSpecificOutput":{"decision":{"behavior":"allow","updatedPermissions":[{"behavior":"allow","destination":"localSettings","rules":[{"ruleContent":"rm -rf node_modules","toolName":"Bash"}],"type":"addRules"}]},"hookEventName":"PermissionRequest"}}"#)
    }

    @Test func allowAlwaysWithoutARuleMatchesAllow() throws {
        let request = try #require(PendingRequest(toolName: "Bash", toolInput: .object(["command": .string("ls")])))
        #expect(request.alwaysAllowRule == nil)
        #expect(PermissionDecision.allowAlways.reply(for: request) == PermissionDecision.allow.reply(for: request))
    }

    @Test func describesWhereTheRuleIsSaved() throws {
        let rules = [("Bash", "rm -rf node_modules" as String?), ("Read", nil)]
        let destinations = [
            "localSettings": "Bash(rm -rf node_modules), Read for this project, only you",
            "projectSettings": "Bash(rm -rf node_modules), Read for this project",
            "userSettings": "Bash(rm -rf node_modules), Read for all projects",
            "session": "Bash(rm -rf node_modules), Read for this session",
        ]
        for (destination, description) in destinations {
            let request = try #require(PendingRequest(toolName: "Bash", toolInput: nil, permissionSuggestions: [Self.suggestion(destination: destination, rules: rules)]))
            #expect(request.alwaysAllowDescription == description)
        }
    }

    @Test func usesTheFirstAllowAddRulesSuggestion() throws {
        let setMode: JSONValue = .object(["type": .string("setMode"), "behavior": .string("allow"), "destination": .string("session")])
        let denyRule = Self.suggestion(behavior: "deny", destination: "session", rules: [("Bash", "ls")])
        let match = Self.suggestion(destination: "session", rules: [("Bash", "ls")])
        let later = Self.suggestion(destination: "userSettings", rules: [("Read", nil)])
        let request = try #require(PendingRequest(toolName: "Bash", toolInput: nil, permissionSuggestions: [setMode, denyRule, match, later]))
        #expect(request.alwaysAllowRule == match)
        #expect(request.alwaysAllowDescription == "Bash(ls) for this session")
    }

    @Test func questionsDoNotOfferAlwaysAllow() throws {
        let input: JSONValue = .object([
            "questions": .array([.object(["question": .string("Which?"), "options": .array([.object(["label": .string("A")])])])]),
        ])
        let request = try #require(PendingRequest(toolName: "AskUserQuestion", toolInput: input, permissionSuggestions: [Self.suggestion(destination: "localSettings", rules: [("AskUserQuestion", nil)])]))
        #expect(request.isQuestion)
        #expect(request.alwaysAllowRule == nil)
        #expect(request.alwaysAllowDescription == nil)
    }

    private static func suggestion(behavior: String = "allow", destination: String, rules: [(String, String?)]) -> JSONValue {
        .object([
            "type": .string("addRules"),
            "behavior": .string(behavior),
            "destination": .string(destination),
            "rules": .array(rules.map { tool, content in
                var rule: [String: JSONValue] = ["toolName": .string(tool)]
                if let content {
                    rule["ruleContent"] = .string(content)
                }
                return .object(rule)
            }),
        ])
    }
}
