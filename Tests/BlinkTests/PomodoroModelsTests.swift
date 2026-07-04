import Testing
import Foundation
@testable import BlinkCore

@Suite("Pomodoro models")
struct PomodoroModelsTests {

    @Test func phaseDurations() {
        let s = PomodoroSettings()
        #expect(s.focusSeconds == 25 * 60)
        #expect(s.shortBreakSeconds == 5 * 60)
        #expect(s.longBreakSeconds == 15 * 60)
        #expect(s.duration(for: .focus) == 25 * 60)
        #expect(s.duration(for: .shortBreak) == 5 * 60)
        #expect(s.duration(for: .longBreak) == 15 * 60)
    }

    @Test func settingsCodableRoundTrip() throws {
        var s = PomodoroSettings()
        s.focusMinutes = 40
        s.shortBreakMinutes = 10
        s.ttsRate = 0.7

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(PomodoroSettings.self, from: data)

        #expect(decoded == s)
        #expect(decoded.focusMinutes == 40)
        #expect(decoded.shortBreakMinutes == 10)
        #expect(decoded.ttsRate == 0.7)
    }

    @Test func statsRegistration() {
        var stats = PomodoroStats()
        stats.registerFocusCompletion()
        stats.registerFocusCompletion()
        #expect(stats.completedFocus == 2)
        #expect(stats.completedToday == 2)
        stats.resetTodayIfNeeded()
        #expect(stats.completedToday == 0)
        #expect(stats.completedFocus == 2)
    }

    @Test func phaseMetadata() {
        #expect(!PomodoroPhase.focus.label.isEmpty)
        #expect(!PomodoroPhase.focus.systemImage.isEmpty)
        #expect(PomodoroPhase.allCases.count == 4)
        #expect(PomodoroPhase.focus.gradient.count == 2)
    }

    @Test func durationForPausedPhase() {
        let s = PomodoroSettings()
        #expect(s.duration(for: .paused) == 0)
    }

    @Test("cyclic gradient matches expected color stacks")
    func phaseGradientColors() {
        #expect(PomodoroPhase.focus.gradient == [.paletteFocusStart, .paletteFocusEnd])
        #expect(PomodoroPhase.shortBreak.gradient == [.paletteBreakStart, .paletteBreakEnd])
        #expect(PomodoroPhase.longBreak.gradient == [.paletteLongStart, .paletteLongEnd])
        #expect(PomodoroPhase.paused.gradient == [.paletteMutedStart, .paletteMutedEnd])
    }
}