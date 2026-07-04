import Foundation
import SwiftUI

public enum PomodoroPhase: String, Codable, CaseIterable, Sendable {
    case focus
    case shortBreak
    case longBreak
    case paused

    public var label: String {
        switch self {
        case .focus:      return "Diqqat"
        case .shortBreak: return "Tanaffus"
        case .longBreak:  return "Uzun tanaffus"
        case .paused:     return "Pauza"
        }
    }

    public var systemImage: String {
        switch self {
        case .focus:      return "brain.head.profile.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak:  return "leaf.fill"
        case .paused:     return "pause.circle.fill"
        }
    }

    public var gradient: [Color] {
        switch self {
        case .focus:      return [.paletteFocusStart, .paletteFocusEnd]
        case .shortBreak: return [.paletteBreakStart, .paletteBreakEnd]
        case .longBreak:  return [.paletteLongStart, .paletteLongEnd]
        case .paused:     return [.paletteMutedStart, .paletteMutedEnd]
        }
    }

    public var glow: Color {
        switch self {
        case .focus:      return .paletteFocusStart
        case .shortBreak: return .paletteBreakStart
        case .longBreak:  return .paletteLongStart
        case .paused:     return .paletteMutedStart
        }
    }
}