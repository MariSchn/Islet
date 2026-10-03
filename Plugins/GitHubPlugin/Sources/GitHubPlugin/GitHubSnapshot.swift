import Foundation

struct GitHubSnapshot: Sendable, Equatable {
    var mine: [PullRequest]
    var reviewRequested: [PullRequest]

    init(mine: [PullRequest], reviewRequested: [PullRequest]) {
        self.mine = mine.sorted { $0.updatedAt > $1.updatedAt }
        self.reviewRequested = reviewRequested.sorted { $0.updatedAt > $1.updatedAt }
    }

    var isEmpty: Bool {
        mine.isEmpty && reviewRequested.isEmpty
    }

    static func decode(_ data: Data) throws -> GitHubSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(Response.self, from: data)
        guard let data = response.data else {
            throw GitHubError.failed(response.errors?.first?.message ?? "GitHub returned no data.")
        }
        return GitHubSnapshot(
            mine: data.mine.nodes.compactMap(\.pullRequest),
            reviewRequested: data.review.nodes.compactMap(\.pullRequest)
        )
    }

    private struct Response: Decodable {
        var data: Sections?
        var errors: [Message]?
    }

    private struct Message: Decodable {
        var message: String
    }

    private struct Sections: Decodable {
        var mine: Search
        var review: Search
    }

    private struct Search: Decodable {
        var nodes: [Node]
    }

    private struct Node: Decodable {
        var number: Int?
        var title: String?
        var url: URL?
        var isDraft: Bool?
        var reviewDecision: String?
        var updatedAt: Date?
        var author: Login?
        var repository: Repository?

        var pullRequest: PullRequest? {
            guard let number, let title, let url, let updatedAt, let repository else { return nil }
            return PullRequest(
                number: number,
                title: title,
                url: url,
                repository: repository.nameWithOwner,
                isDraft: isDraft ?? false,
                reviewDecision: reviewDecision.flatMap(ReviewDecision.init(rawValue:)),
                author: author?.login,
                updatedAt: updatedAt
            )
        }
    }

    private struct Login: Decodable {
        var login: String
    }

    private struct Repository: Decodable {
        var nameWithOwner: String
    }
}

struct PullRequest: Sendable, Equatable, Identifiable {
    var number: Int
    var title: String
    var url: URL
    var repository: String
    var isDraft: Bool
    var reviewDecision: ReviewDecision?
    var author: String?
    var updatedAt: Date

    var id: URL { url }

    var reference: String {
        "\(repository) #\(number)"
    }

    var reviewChip: ReviewChip? {
        if isDraft { return .draft }
        switch reviewDecision {
        case .approved: return .approved
        case .changesRequested: return .changesRequested
        case .reviewRequired: return .reviewRequired
        case nil: return nil
        }
    }
}

enum ReviewDecision: String, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum ReviewChip: Sendable {
    case approved
    case changesRequested
    case reviewRequired
    case draft

    var title: String {
        switch self {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .reviewRequired: "Review required"
        case .draft: "Draft"
        }
    }
}
