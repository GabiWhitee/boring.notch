//
//  PomodoroManager.swift
//  boringNotch
//
//  Pomodoro / focus timer feature.
//

import AppKit
import Combine
import Defaults
import SwiftUI

enum PomodoroPhase: Equatable {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var symbol: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }

    var accent: Color {
        switch self {
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }
}

/// Drives a classic Pomodoro cycle: focus sessions interleaved with short breaks
/// and a long break every N sessions. Durations are read live from `Defaults`.
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var phase: PomodoroPhase = .work
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var timeRemaining: Int = Defaults[.pomodoroWorkMinutes] * 60
    /// Number of completed focus sessions in the current cycle.
    @Published private(set) var completedWorkSessions: Int = 0

    private var cancellable: AnyCancellable?

    private init() {}

    // MARK: - Derived values

    var totalTime: Int { duration(for: phase) }

    var progress: Double {
        let total = totalTime
        guard total > 0 else { return 0 }
        let elapsed = Double(total - timeRemaining)
        return min(max(elapsed / Double(total), 0), 1)
    }

    var formattedTime: String {
        let minutes = max(0, timeRemaining) / 60
        let seconds = max(0, timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func duration(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .work: return max(1, Defaults[.pomodoroWorkMinutes]) * 60
        case .shortBreak: return max(1, Defaults[.pomodoroShortBreakMinutes]) * 60
        case .longBreak: return max(1, Defaults[.pomodoroLongBreakMinutes]) * 60
        }
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        // If a previous phase finished at 0, roll into the fresh duration.
        if timeRemaining <= 0 {
            timeRemaining = duration(for: phase)
        }
        isRunning = true
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        isRunning = false
        cancellable?.cancel()
        cancellable = nil
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Resets the remaining time of the current phase without leaving it.
    func reset() {
        pause()
        timeRemaining = duration(for: phase)
    }

    /// Resets the whole cycle back to the first focus session.
    func resetAll() {
        pause()
        phase = .work
        completedWorkSessions = 0
        timeRemaining = duration(for: .work)
    }

    /// Skips to the next phase, staying paused.
    func skip() {
        advancePhase()
        pause()
    }

    /// Called when durations change in settings while idle so the UI reflects them.
    func syncDurationsIfIdle() {
        guard !isRunning else { return }
        timeRemaining = duration(for: phase)
    }

    // MARK: - Internal

    private func tick() {
        guard isRunning else { return }
        if timeRemaining > 0 {
            timeRemaining -= 1
        }
        if timeRemaining <= 0 {
            phaseCompleted()
        }
    }

    private func phaseCompleted() {
        pause()
        if Defaults[.pomodoroPlaySound] {
            NSSound(named: "Glass")?.play()
        }
        advancePhase()
        if Defaults[.pomodoroAutoStartNext] {
            start()
        }
    }

    private func advancePhase() {
        switch phase {
        case .work:
            completedWorkSessions += 1
            let sessionsBeforeLong = max(1, Defaults[.pomodoroSessionsBeforeLongBreak])
            phase = (completedWorkSessions % sessionsBeforeLong == 0) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            phase = .work
        }
        timeRemaining = duration(for: phase)
    }
}
