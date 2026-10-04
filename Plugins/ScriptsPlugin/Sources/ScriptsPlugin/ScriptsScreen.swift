import SwiftUI

struct ScriptsScreen: View {
    let controller: ScriptsController

    private var store: ScriptActivityStore { controller.store }

    var body: some View {
        if let serverError = controller.serverError {
            Text(serverError)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.activities.isEmpty {
            VStack(spacing: 4) {
                Text("No activities")
                    .font(.system(size: 13, weight: .medium))
                Text("Scripts show up here. Install the command-line tool in the Scripts settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.newestFirst) { activity in
                        ScriptActivityRow(activity: activity) { store.remove(id: activity.id) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct ScriptActivityRow: View {
    let activity: ScriptActivity
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.text)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if let progress = activity.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }
            }
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(RelativeDateTimeFormatter().localizedString(for: activity.updatedAt, relativeTo: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove")
            .accessibilityLabel("Remove")
        }
        .frame(height: ScriptsPlugin.rowHeight)
    }
}
