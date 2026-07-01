//
//  PomodoroView.swift
//  boringNotch
//
//  Open-notch tab + settings for the Pomodoro timer.
//

import Defaults
import SwiftUI

// MARK: - Notch tab

struct PomodoroView: View {
    @ObservedObject private var pomodoro = PomodoroManager.shared

    private var sessionsBeforeLong: Int {
        max(1, Defaults[.pomodoroSessionsBeforeLongBreak])
    }

    /// How many of the dots in the current cycle are filled.
    private var filledDots: Int {
        let inCycle = pomodoro.completedWorkSessions % sessionsBeforeLong
        // When we've just wrapped to a long break, show the ring as full.
        return (pomodoro.completedWorkSessions > 0 && inCycle == 0) ? sessionsBeforeLong : inCycle
    }

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            timerRing
            VStack(spacing: 14) {
                sessionDots
                controls
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                statsColumn
                goalBar
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(pomodoro.completedToday) today", systemImage: "checkmark.circle.fill")
            Label(pomodoro.focusTimeTodayText + " focused", systemImage: "clock.fill")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.gray)
    }

    private var goalBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: pomodoro.goalReached ? "checkmark.seal.fill" : "target")
                    .font(.system(size: 9))
                    .foregroundStyle(pomodoro.goalReached ? .green : .gray)
                Text("Daily goal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.gray)
                Spacer(minLength: 8)
                Text("\(pomodoro.completedToday) / \(pomodoro.dailyGoal)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(pomodoro.goalReached ? .green : .white)
            }
            ProgressView(value: pomodoro.dailyGoalProgress)
                .tint(pomodoro.goalReached ? .green : PomodoroPhase.work.accent)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
        }
        .frame(width: 170)
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.22), lineWidth: 6)
            Circle()
                .trim(from: 0, to: pomodoro.progress)
                .stroke(
                    pomodoro.phase.accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: pomodoro.progress)
            VStack(spacing: 2) {
                Text(pomodoro.formattedTime)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                HStack(spacing: 3) {
                    Image(systemName: pomodoro.phase.symbol)
                        .font(.system(size: 9))
                    Text(pomodoro.phase.title)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.gray)
            }
        }
        .frame(width: 116, height: 116)
    }

    private var sessionDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<sessionsBeforeLong, id: \.self) { index in
                Circle()
                    .fill(index < filledDots ? PomodoroPhase.work.accent : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            circleButton(icon: "arrow.counterclockwise", size: 34) {
                pomodoro.reset()
            }

            Button {
                pomodoro.toggle()
            } label: {
                Circle()
                    .fill(pomodoro.phase.accent)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)

            circleButton(icon: "forward.end.fill", size: 34) {
                pomodoro.skip()
            }
        }
    }

    private func circleButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: .secondarySystemFill))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

struct PomodoroSettings: View {
    @ObservedObject private var pomodoro = PomodoroManager.shared

    @Default(.enablePomodoro) var enablePomodoro
    @Default(.pomodoroWorkMinutes) var workMinutes
    @Default(.pomodoroShortBreakMinutes) var shortBreakMinutes
    @Default(.pomodoroLongBreakMinutes) var longBreakMinutes
    @Default(.pomodoroSessionsBeforeLongBreak) var sessionsBeforeLongBreak
    @Default(.pomodoroDailyGoal) var dailyGoal

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enablePomodoro) {
                    Text("Show Pomodoro tab")
                }
            } footer: {
                Text("Adds a focus-timer tab next to Home and Shelf in the open notch.")
            }

            Section(header: Text("Durations")) {
                Stepper(value: $workMinutes, in: 1...120) {
                    LabeledContent("Focus", value: "\(workMinutes) min")
                }
                Stepper(value: $shortBreakMinutes, in: 1...60) {
                    LabeledContent("Short break", value: "\(shortBreakMinutes) min")
                }
                Stepper(value: $longBreakMinutes, in: 1...60) {
                    LabeledContent("Long break", value: "\(longBreakMinutes) min")
                }
                Stepper(value: $sessionsBeforeLongBreak, in: 1...12) {
                    LabeledContent("Sessions before long break", value: "\(sessionsBeforeLongBreak)")
                }
            }

            Section(header: Text("Daily goal")) {
                Stepper(value: $dailyGoal, in: 1...20) {
                    LabeledContent("Focus sessions per day", value: "\(dailyGoal)")
                }
            }

            Section(header: Text("Behavior")) {
                Defaults.Toggle(key: .pomodoroAutoStartNext) {
                    Text("Auto-start next phase")
                }
                Defaults.Toggle(key: .pomodoroPlaySound) {
                    Text("Play sound when a phase ends")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Pomodoro")
        .onChange(of: workMinutes) { _, _ in pomodoro.syncDurationsIfIdle() }
        .onChange(of: shortBreakMinutes) { _, _ in pomodoro.syncDurationsIfIdle() }
        .onChange(of: longBreakMinutes) { _, _ in pomodoro.syncDurationsIfIdle() }
    }
}
