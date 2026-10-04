import SwiftUI

struct AgentsScreen: View {
    let controller: AgentsController
    @Environment(\.notchAnimation) private var animation
    @State private var installError: String?
    @State private var frozenOrder: [String]?

    var body: some View {
        VStack(spacing: AgentsPlugin.rowSpacing) {
            if let usage = controller.visibleUsage {
                UsageBar(usage: usage, showsResetTimes: controller.display.showsResetTimes, dailyCost: controller.dailyCost)
                    .frame(height: AgentsPlugin.usageBarHeight)
            }
            if let quota = controller.visibleAntigravityQuota {
                AntigravityQuotaBar(quota: quota, showsResetTimes: controller.display.showsResetTimes)
                    .frame(height: AgentsPlugin.usageBarHeight)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if controller.store.sessions.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                if let error = controller.serverError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else if !controller.installedHooks.isEmpty {
                    Text("No agent sessions")
                        .foregroundStyle(.secondary)
                    Text("Sessions started after installing the hooks appear here once you send a prompt.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Agent hooks are not installed")
                        .foregroundStyle(.secondary)
                    Button("Install Hooks") {
                        do {
                            try controller.installHooks(for: .claudeCode)
                            installError = nil
                        } catch {
                            installError = error.localizedDescription
                        }
                    }
                    .buttonStyle(.bordered)
                    if let installError {
                        Text(installError)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { controller.refreshInstallState() }
        } else {
            ScrollView {
                VStack(spacing: AgentsPlugin.rowSpacing) {
                    ForEach(SessionOrder.applying(frozen: frozenOrder, to: controller.store.orderedSessions)) { session in
                        SessionRow(
                            session: session,
                            terminal: controller.terminal(for: session),
                            isExpanded: controller.expandedSessionIDs.contains(session.id),
                            historyLength: controller.display.historyLength,
                            showTerminal: { controller.showTerminal(for: session) },
                            isMuted: controller.mutedSessionIDs.contains(session.id),
                            toggleMute: { controller.toggleMute(session.id) },
                            dismiss: { controller.store.dismiss(session.id) },
                            toggleExpanded: { controller.toggleExpanded(session.id) },
                            decide: { controller.decide($0, $1) }
                        )
                    }
                }
                .animation(animation, value: controller.expandedSessionIDs)
                .animation(animation, value: SessionOrder.applying(frozen: frozenOrder, to: controller.store.orderedSessions).map(\.id))
            }
            .onHover { isHovering in
                frozenOrder = isHovering ? controller.store.orderedSessions.map(\.id) : nil
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
