import Testing
import Foundation
@testable import SharinganCore

@Suite("Notch HUD state")
struct NotchHUDStateTests {

    @Test("an idle, enabled HUD shows the bare island")
    func idleByDefault() {
        #expect(NotchHUDState().size == .idle)
    }

    @Test("disabling hides it in every other condition")
    func disabledWins() {
        var s = NotchHUDState()
        s.enabled = false
        s.hovering = true
        s.engaged = true
        s.activity = .sessionDone
        #expect(s.size == .hidden)
    }

    @Test("a running session shows the live ears")
    func engagedIsLive() {
        var s = NotchHUDState()
        s.engaged = true
        #expect(s.size == .live)
    }

    @Test("hover expands, from idle and from live alike")
    func hoverExpands() {
        var s = NotchHUDState()
        s.hovering = true
        #expect(s.size == .expanded)
        s.engaged = true
        #expect(s.size == .expanded)
    }

    @Test("an activity announcement preempts idle and live but not hover")
    func activityPreempts() {
        var s = NotchHUDState()
        s.activity = .breakStarted
        #expect(s.size == .activity)
        s.engaged = true
        #expect(s.size == .activity)
        s.hovering = true
        #expect(s.size == .expanded)
    }

    @Test("activities are suppressed when the user turned them off")
    func activityCanBeDisabled() {
        var s = NotchHUDState()
        s.liveActivityEnabled = false
        s.activity = .sessionDone
        #expect(s.size == .idle)
        s.engaged = true
        #expect(s.size == .live)
    }

    @Test("the break overlay hides the HUD entirely")
    func breakOverlayHides() {
        var s = NotchHUDState()
        s.engaged = true
        s.breakOverlayUp = true
        #expect(s.size == .hidden)
        s.hovering = true
        #expect(s.size == .hidden)
    }

    @Test("activity messages carry the task title")
    func activityMessages() {
        #expect(NotchActivity.taskDone("Ship it").message.contains("Ship it"))
        #expect(!NotchActivity.sessionDone.message.isEmpty)
        #expect(!NotchActivity.breakStarted.systemImage.isEmpty)
    }
}
