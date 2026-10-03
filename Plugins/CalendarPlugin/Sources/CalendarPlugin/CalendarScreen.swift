import AppKit
import SwiftUI

struct CalendarScreen: View {
    let controller: CalendarController

    var body: some View {
        if controller.authorization == .fullAccess {
            AgendaView(agenda: controller.agenda, now: controller.referenceDate)
        } else {
            CalendarAccessView(controller: controller)
        }
    }
}

private struct AgendaView: View {
    let agenda: CalendarAgenda
    let now: Date

    var body: some View {
        if agenda.rowCount == 0 {
            VStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No more events today or tomorrow")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(agenda.sections.enumerated()), id: \.element.id) { index, section in
                    Text(section.day.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: CalendarPlugin.headerHeight, alignment: .leading)
                        .padding(.top, index > 0 ? CalendarPlugin.sectionSpacing : 0)
                    ForEach(section.events) { event in
                        EventRow(event: event, now: now)
                            .frame(height: CalendarPlugin.rowHeight)
                    }
                }
                if agenda.moreCount > 0 {
                    Text("+\(agenda.moreCount) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(height: CalendarPlugin.moreLineHeight, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(event.color))
                .frame(width: 8, height: 8)
            Text(event.timeLabel(at: now))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(event.isInProgress(at: now) ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 128, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if event.showsJoin(at: now), let url = event.meetingURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Join", systemImage: "video.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

struct CalendarAccessView: View {
    let controller: CalendarController

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            if controller.authorization == .notDetermined {
                Button("Allow Calendar Access") { Task { await controller.requestAccess() } }
                    .buttonStyle(.bordered)
            } else {
                Text("Calendar access is off")
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings") { EventKitSource.openPrivacySettings() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
