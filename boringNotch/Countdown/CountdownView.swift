//
//  CountdownView.swift
//  boringNotch
//
//  Home widget: days remaining until a chosen date (birthday, deadline, trip…).
//

import Defaults
import SwiftUI

// MARK: - Home widget

struct CountdownView: View {
    @Default(.countdownLabel) private var label
    @Default(.countdownDate) private var date

    private var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    private var bigText: String {
        let days = daysRemaining
        if days == 0 { return "Today!" }
        return "\(abs(days))"
    }

    private var subText: String {
        let days = daysRemaining
        switch days {
        case 0: return "is the day 🎉"
        case 1: return "day to go"
        case -1: return "day ago"
        case let d where d < 0: return "days ago"
        default: return "days to go"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13))
                    .foregroundStyle(.pink)
                Text(label.isEmpty ? "Countdown" : label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(bigText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subText)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }
            Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.system(size: 9))
                .foregroundStyle(.gray.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.35))
        )
    }
}

// MARK: - Settings

struct CountdownSettings: View {
    @Default(.countdownLabel) private var label

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showCountdown) {
                    Text("Show countdown in Home")
                }
            } footer: {
                Text("Shows the days remaining until a date, next to the calendar.")
            }

            Section(header: Text("Event")) {
                TextField("Label", text: $label, prompt: Text("e.g. Vacation"))
                    .textFieldStyle(.roundedBorder)
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { Defaults[.countdownDate] },
                        set: { Defaults[.countdownDate] = $0 }
                    ),
                    displayedComponents: .date
                )
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Countdown")
    }
}
