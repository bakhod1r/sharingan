import Testing
import Foundation
@testable import SharinganCore

@Suite("Notch settings")
struct NotchSettingsTests {

    @Test("defaults: HUD on, both ears, activities on, every panel section on")
    func defaults() {
        let s = PomodoroSettings()
        #expect(s.notchHUDEnabled)
        #expect(s.notchEars == .both)
        #expect(s.notchLiveActivity)
        // The content switches default to the always-on behavior the HUD
        // shipped with: turning none of them off changes nothing.
        #expect(s.notchShowTimerControls)
        #expect(s.notchShowTasks)
        #expect(s.notchShowQuickActions)
        #expect(s.notchShowStatusStrip)
        #expect(s.notchTaskRows == NotchTaskRows.defaultLimit)
        #expect(s.notchContent == NotchContentConfig.default)
    }

    @Test("settings survive a codable round trip")
    func roundTrip() throws {
        var s = PomodoroSettings()
        s.notchHUDEnabled = false
        s.notchEars = .trailingOnly
        s.notchLiveActivity = false
        s.notchShowTimerControls = false
        s.notchShowTasks = false
        s.notchShowQuickActions = false
        s.notchShowStatusStrip = false
        s.notchTaskRows = 3
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PomodoroSettings.self, from: data)
        #expect(back.notchHUDEnabled == false)
        #expect(back.notchEars == .trailingOnly)
        #expect(back.notchLiveActivity == false)
        #expect(back.notchShowTimerControls == false)
        #expect(back.notchShowTasks == false)
        #expect(back.notchShowQuickActions == false)
        #expect(back.notchShowStatusStrip == false)
        #expect(back.notchTaskRows == 3)
    }

    @Test("settings saved before the notch HUD existed still decode")
    func decodesLegacyJSON() throws {
        // A settings blob written by an older build has no notch keys at all.
        var s = PomodoroSettings()
        s.longBreakMinutes = 12
        let data = try JSONEncoder().encode(s)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["notchHUDEnabled", "notchEars", "notchLiveActivity",
                    "notchShowTimerControls", "notchShowTasks",
                    "notchShowQuickActions", "notchShowStatusStrip",
                    "notchTaskRows"] {
            json.removeValue(forKey: key)
        }
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let back = try JSONDecoder().decode(PomodoroSettings.self, from: legacy)
        #expect(back.longBreakMinutes == 12)   // the rest of the blob survived
        #expect(back.notchHUDEnabled)          // and the new keys took their defaults
        #expect(back.notchEars == .both)
        #expect(back.notchShowTimerControls)
        #expect(back.notchShowTasks)
        #expect(back.notchShowQuickActions)
        #expect(back.notchShowStatusStrip)
        #expect(back.notchTaskRows == NotchTaskRows.defaultLimit)
        // …and the projection the geometry reads is the shipped one, so an
        // upgrade cannot silently resize the island.
        #expect(back.notchContent == NotchContentConfig.default)
    }

    /// A blob written by a *newer* build, or hand-edited, can carry a row count
    /// outside the range the panel was measured for. The geometry clamps rather
    /// than trusting it — an unclamped 40 would size the island off the screen.
    @Test("the task-row count is clamped to the range the panel is measured for")
    func taskRowsAreClamped() {
        var s = PomodoroSettings()
        s.notchTaskRows = 40
        #expect(s.notchContent.clampedTaskRows == NotchContentConfig.taskRowRange.upperBound)
        s.notchTaskRows = 0
        #expect(s.notchContent.clampedTaskRows == NotchContentConfig.taskRowRange.lowerBound)
        s.notchTaskRows = 4
        #expect(s.notchContent.clampedTaskRows == 4)
    }

    @Test("the content config is the settings, projected")
    func contentProjection() {
        var s = PomodoroSettings()
        s.notchEars = .none
        s.notchShowTasks = false
        s.notchTaskRows = 3
        let c = s.notchContent
        #expect(c.ears == .none)
        #expect(c.showTasks == false)
        #expect(c.showTimerControls)
        #expect(c.taskRows == 3)
    }

    @Test("each ears mode names how many ears it grows")
    func earCounts() {
        #expect(NotchEarsMode.both.earCount == 2)
        #expect(NotchEarsMode.trailingOnly.earCount == 1)
        #expect(NotchEarsMode.none.earCount == 0)
        #expect(NotchEarsMode.both.showsLeadingEar)
        #expect(!NotchEarsMode.trailingOnly.showsLeadingEar)
        #expect(NotchEarsMode.trailingOnly.showsTrailingEar)
        #expect(!NotchEarsMode.none.showsTrailingEar)
    }

    @Test("every ears mode has a label and is codable")
    func earsModes() throws {
        for mode in NotchEarsMode.allCases {
            #expect(!mode.label.isEmpty)
            let data = try JSONEncoder().encode([mode])
            #expect(try JSONDecoder().decode([NotchEarsMode].self, from: data) == [mode])
        }
    }
}
