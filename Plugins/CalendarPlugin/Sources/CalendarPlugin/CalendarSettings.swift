import SwiftUI

struct CalendarSettings: View {
    @Bindable var controller: CalendarController

    private struct Account: Identifiable {
        let id: String
        let title: String
        let calendars: [CalendarInfo]
    }

    private var accounts: [Account] {
        Dictionary(grouping: controller.calendars, by: \.accountID)
            .map { id, calendars in
                Account(
                    id: id,
                    title: calendars.first?.account ?? "",
                    calendars: calendars.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            switch controller.authorization {
            case .fullAccess:
                Section {
                    Toggle("Show all-day events", isOn: $controller.includesAllDay)
                    Toggle("Show the next event in the collapsed notch", isOn: $controller.showsPill)
                    Picker("Starting", selection: $controller.leadMinutes) {
                        ForEach(CalendarController.leadMinuteChoices, id: \.self) { minutes in
                            Text("\(minutes) minutes before").tag(minutes)
                        }
                    }
                    .disabled(!controller.showsPill)
                } header: {
                    Text("Events")
                }
                .onAppear { controller.reload() }
                ForEach(accounts) { account in
                    Section(account.title.isEmpty ? "Other Calendars" : account.title) {
                        ForEach(account.calendars) { calendar in
                            Toggle(isOn: selection(for: calendar)) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(calendar.color))
                                        .frame(width: 8, height: 8)
                                    Text(calendar.title)
                                }
                            }
                        }
                    }
                }
            case .notDetermined:
                Section {
                    LabeledContent("Islet needs access to your calendars to show your events.") {
                        Button("Allow Access") { Task { await controller.requestAccess() } }
                    }
                }
                .onAppear { controller.reload() }
            case .denied, .restricted:
                Section {
                    LabeledContent("Calendar access is turned off for Islet.") {
                        Button("Open Privacy Settings") { EventKitSource.openPrivacySettings() }
                    }
                } footer: {
                    Text("Turn on Islet under Privacy & Security › Calendars.")
                }
                .onAppear { controller.reload() }
            }
        }
    }

    private func selection(for calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { controller.isSelected(calendar) },
            set: { controller.setSelected($0, for: calendar) }
        )
    }
}
