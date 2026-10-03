import IsletCore
import SwiftUI

struct GitHubChange: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case checksFailed
        case checksPassed
        case approved
        case changesRequested
        case reviewRequested
    }

    var kind: Kind
    var pullRequest: PullRequest

    var priority: PillStatus.Priority {
        switch kind {
        case .checksFailed, .changesRequested, .reviewRequested: .attention
        case .checksPassed, .approved: .info
        }
    }

    var text: String {
        let reference = "\(pullRequest.repositoryName) #\(pullRequest.number)"
        return switch kind {
        case .checksFailed: "\(reference) checks failed"
        case .checksPassed: "\(reference) checks passed"
        case .approved: "\(reference) approved"
        case .changesRequested: "\(reference) changes requested"
        case .reviewRequested: "Review requested: \(reference)"
        }
    }

    var systemImage: String {
        switch kind {
        case .checksFailed: "xmark.circle.fill"
        case .checksPassed: "checkmark.circle.fill"
        case .approved: "checkmark.seal.fill"
        case .changesRequested: "exclamationmark.bubble.fill"
        case .reviewRequested: "arrow.triangle.pull"
        }
    }

    var tint: Color.Resolved {
        switch kind {
        case .checksFailed: GitHubPill.failingTint
        case .checksPassed, .approved: GitHubPill.passingTint
        case .changesRequested, .reviewRequested: Color.Resolved(red: 1, green: 0.62, blue: 0.04)
        }
    }
}

enum GitHubChanges {
    static func changes(from previous: GitHubSnapshot?, to current: GitHubSnapshot) -> [GitHubChange] {
        guard let previous else { return [] }
        let before = Dictionary(previous.mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [GitHubChange] = []
        for pullRequest in current.mine {
            guard let old = before[pullRequest.id] else { continue }
            if old.checks == .pending {
                switch pullRequest.checks {
                case .failing: changes.append(GitHubChange(kind: .checksFailed, pullRequest: pullRequest))
                case .passing: changes.append(GitHubChange(kind: .checksPassed, pullRequest: pullRequest))
                case .pending, nil: break
                }
            }
            if pullRequest.reviewDecision != old.reviewDecision {
                switch pullRequest.reviewDecision {
                case .approved: changes.append(GitHubChange(kind: .approved, pullRequest: pullRequest))
                case .changesRequested: changes.append(GitHubChange(kind: .changesRequested, pullRequest: pullRequest))
                case .reviewRequired, nil: break
                }
            }
        }
        let requested = Set(previous.reviewRequested.map(\.id))
        for pullRequest in current.reviewRequested where !requested.contains(pullRequest.id) {
            changes.append(GitHubChange(kind: .reviewRequested, pullRequest: pullRequest))
        }
        return changes
    }

    static func announcement(from previous: GitHubSnapshot?, to current: GitHubSnapshot) -> PillAnnouncement? {
        announcement(for: changes(from: previous, to: current))
    }

    static func announcement(for changes: [GitHubChange]) -> PillAnnouncement? {
        guard let first = changes.enumerated().max(by: { lhs, rhs in
            lhs.element.priority != rhs.element.priority ? lhs.element.priority < rhs.element.priority : lhs.offset > rhs.offset
        })?.element else { return nil }
        let others = changes.count - 1
        let text = others > 0 ? "\(first.text) and \(others) more" : first.text
        return PillAnnouncement(text: text, systemImage: first.systemImage, tint: first.tint, priority: first.priority)
    }
}

extension PullRequest {
    var repositoryName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}
