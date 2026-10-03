import Foundation
import Testing
@testable import GitHubPlugin

struct GitHubSnapshotTests {
    static let fixture = """
        {
          "data": {
            "mine": {
              "nodes": [
                {
                  "number": 12,
                  "title": "Older change",
                  "url": "https://github.com/acme/app/pull/12",
                  "isDraft": false,
                  "reviewDecision": "APPROVED",
                  "updatedAt": "2026-09-30T08:00:00Z",
                  "repository": { "nameWithOwner": "acme/app" }
                },
                {
                  "number": 15,
                  "title": "Work in progress",
                  "url": "https://github.com/acme/app/pull/15",
                  "isDraft": true,
                  "reviewDecision": null,
                  "updatedAt": "2026-10-02T09:30:00Z",
                  "repository": { "nameWithOwner": "acme/app" }
                },
                {
                  "number": 3,
                  "title": "No review decision",
                  "url": "https://github.com/acme/lib/pull/3",
                  "isDraft": false,
                  "updatedAt": "2026-10-01T10:00:00Z",
                  "repository": { "nameWithOwner": "acme/lib" }
                },
                {}
              ]
            },
            "review": {
              "nodes": [
                {
                  "number": 7,
                  "title": "Please review",
                  "url": "https://github.com/other/tool/pull/7",
                  "isDraft": false,
                  "updatedAt": "2026-10-01T12:00:00Z",
                  "author": { "login": "octocat" },
                  "repository": { "nameWithOwner": "other/tool" }
                },
                {
                  "number": 8,
                  "title": "Ghost author",
                  "url": "https://github.com/other/tool/pull/8",
                  "isDraft": true,
                  "updatedAt": "2026-10-02T12:00:00Z",
                  "author": null,
                  "repository": { "nameWithOwner": "other/tool" }
                }
              ]
            }
          }
        }
        """

    @Test func decodesBothSectionsNewestFirst() throws {
        let snapshot = try GitHubSnapshot.decode(Data(Self.fixture.utf8))
        #expect(snapshot.mine.map(\.number) == [15, 3, 12])
        #expect(snapshot.reviewRequested.map(\.number) == [8, 7])
        #expect(snapshot.mine[0].reference == "acme/app #15")
        #expect(snapshot.mine[0].url == URL(string: "https://github.com/acme/app/pull/15"))
        #expect(snapshot.mine[0].updatedAt == Date(timeIntervalSince1970: 1_790_933_400))
        #expect(snapshot.reviewRequested[1].author == "octocat")
        #expect(snapshot.reviewRequested[0].author == nil)
    }

    @Test func decodesDraftsAndMissingReviewDecisions() throws {
        let snapshot = try GitHubSnapshot.decode(Data(Self.fixture.utf8))
        let draft = try #require(snapshot.mine.first { $0.number == 15 })
        let undecided = try #require(snapshot.mine.first { $0.number == 3 })
        let approved = try #require(snapshot.mine.first { $0.number == 12 })
        #expect(draft.isDraft)
        #expect(draft.reviewDecision == nil)
        #expect(draft.reviewChip == .draft)
        #expect(undecided.reviewDecision == nil)
        #expect(undecided.reviewChip == nil)
        #expect(approved.reviewDecision == .approved)
        #expect(approved.reviewChip == .approved)
    }

    @Test func mapsReviewDecisionsToChips() {
        func chip(_ decision: ReviewDecision?, draft: Bool = false) -> ReviewChip? {
            PullRequest(number: 1, title: "t", url: URL(string: "https://github.com/a/b/pull/1")!, repository: "a/b", isDraft: draft, reviewDecision: decision, updatedAt: .now).reviewChip
        }
        #expect(chip(.approved) == .approved)
        #expect(chip(.changesRequested) == .changesRequested)
        #expect(chip(.reviewRequired) == .reviewRequired)
        #expect(chip(nil) == nil)
        #expect(chip(.approved, draft: true) == .draft)
    }

    @Test func reportsGraphQLErrorsWithoutData() {
        let json = #"{"errors":[{"message":"Something went wrong"}]}"#
        #expect(throws: GitHubError.failed("Something went wrong")) {
            try GitHubSnapshot.decode(Data(json.utf8))
        }
    }

    @Test func rejectsMalformedOutput() {
        #expect(throws: (any Error).self) {
            try GitHubSnapshot.decode(Data("not json".utf8))
        }
    }
}
