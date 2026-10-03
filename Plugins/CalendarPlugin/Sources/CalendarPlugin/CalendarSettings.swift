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
        Form {
            switch controller.authorization {
            case .fullAccess:
                Section {
                    Toggle("Show all-day events", isOn: $controller.includesAllDay)
                }
                Section {
                    Toggle("Show upcoming events in the closed notch", isOn: $controller.showsPill)
                    Picker("Lead time", selection: $controller.leadMinutes) {
                        ForEach(CalendarController.leadMinuteChoices, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .disabled(!controller.showsPill)
                }
                ForEach(accounts) { account in
                    Section(account.title.isEmpty ? "Other" : account.title) {
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
                    HStack {
                        Text("Islet needs access to your calendars to show your events.")
                        Spacer()
                        Button("Allow Calendar Access") { Task { await controller.requestAccess() } }
                    }
                }
            case .denied, .restricted:
                Section {
                    HStack {
                        Text("Calendar access is off")
                        Spacer()
                        Button("Open Privacy Settings") { EventKitSource.openPrivacySettings() }
                    }
                }
            }
        }
        .onAppear { controller.reload() }
    }

    private func selection(for calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { controller.isSelected(calendar) },
            set: { controller.setSelected($0, for: calendar) }
        )
    }
}
