import SwiftUI

struct GitHubScreen: View {
    let controller: GitHubController

    var body: some View {
        switch controller.phase {
        case .loading:
            MessageView(systemImage: nil, text: controller.isOnline ? "Loading pull requests…" : "Waiting for a network connection…", isError: false)
        case .ghMissing, .notLoggedIn:
            MessageView(systemImage: "terminal", text: GitHubError(controller.phase)?.localizedDescription ?? "", isError: false)
        case .failed(let message):
            MessageView(systemImage: "exclamationmark.triangle", text: message, isError: true)
        case .loaded(let snapshot) where snapshot.isEmpty:
            MessageView(systemImage: "checkmark.circle", text: "No open pull requests", isError: false)
        case .loaded(let snapshot):
            PullRequestList(snapshot: snapshot)
        }
    }
}

private extension GitHubError {
    init?(_ phase: GitHubPhase) {
        switch phase {
        case .ghMissing: self = .ghMissing
        case .notLoggedIn: self = .notLoggedIn
        default: return nil
        }
    }
}

private struct MessageView: View {
    let systemImage: String?
    let text: String
    let isError: Bool

    var body: some View {
        VStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PullRequestList: View {
    let snapshot: GitHubSnapshot

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: GitHubPlugin.sectionSpacing) {
                if !snapshot.mine.isEmpty {
                    PullRequestSection(title: "My pull requests", pullRequests: snapshot.mine, showsReview: true)
                }
                if !snapshot.reviewRequested.isEmpty {
                    PullRequestSection(title: "Review requested", pullRequests: snapshot.reviewRequested, showsReview: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct PullRequestSection: View {
    let title: String
    let pullRequests: [PullRequest]
    let showsReview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: GitHubPlugin.sectionHeaderHeight, alignment: .leading)
            ForEach(pullRequests) { pullRequest in
                PullRequestRow(pullRequest: pullRequest, showsReview: showsReview)
            }
        }
    }
}

private struct PullRequestRow: View {
    let pullRequest: PullRequest
    let showsReview: Bool
    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    private var subtitle: String {
        guard !showsReview, let author = pullRequest.author else { return pullRequest.reference }
        return "\(pullRequest.reference) · \(author)"
    }

    var body: some View {
        Button {
            openURL(pullRequest.url)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(pullRequest.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if showsReview, let chip = pullRequest.reviewChip {
                    ReviewChipView(chip: chip)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: GitHubPlugin.rowHeight)
            .background(isHovered ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(pullRequest.url.absoluteString)
    }
}

private struct ReviewChipView: View {
    let chip: ReviewChip

    private var style: AnyShapeStyle {
        switch chip {
        case .approved: AnyShapeStyle(.green)
        case .changesRequested: AnyShapeStyle(.orange)
        case .reviewRequired: AnyShapeStyle(.secondary)
        case .draft: AnyShapeStyle(.tertiary)
        }
    }

    var body: some View {
        Text(chip.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(style)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(style, lineWidth: 1))
    }
}
