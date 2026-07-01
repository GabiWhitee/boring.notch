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
        HStack(spacing: 28) {
            timerRing
            VStack(alignment: .leading, spacing: 14) {
                sessionDots
                controls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
