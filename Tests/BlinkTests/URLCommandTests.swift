import Testing
import Foundation
@testable import BlinkCore

/// `sharingan://` URL scheme → URLCommand mapping (the Shortcuts/Raycast
/// automation surface; App Intents aren't possible in pure SwiftPM).
@Suite("URL command router")
struct URLCommandTests {

    private func parse(_ s: String, now: Date = Date()) -> URLCommand? {
        guard let url = URL(string: s) else { return nil }
        return URLCommandRouter.parse(url, now: now)
    }

    // MARK: - start

    @Test func startBareDefaultsDuration() {
        #expect(parse("sharingan://start") == .start(nil))
    }

    @Test func startWithMinutesConvertsToSeconds() {
        #expect(parse("sharingan://start?minutes=25") == .start(25 * 60))
    }

    @Test func startWithFractionalMinutes() {
        #expect(parse("sharingan://start?minutes=1.5") == .start(90))
    }

    @Test func startWithNonPositiveMinutesIsRejected() {
        #expect(parse("sharingan://start?minutes=0") == nil)
        #expect(parse("sharingan://start?minutes=-5") == nil)
        #expect(parse("sharingan://start?minutes=abc") == nil)
    }

    @Test func startWithNaturalLanguageDuration() {
        #expect(parse("sharingan://start?input=45m") == .start(45 * 60))
    }

    @Test func startWithClockTargetComputesIntervalFromNow() throws {
        // Pin "now" to 09:00 local so "5pm" is deterministically 8 h away.
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9; comps.minute = 0; comps.second = 0
        let now = try #require(Calendar.current.date(from: comps))
        let cmd = try #require(parse("sharingan://start?input=5pm", now: now))
        guard case .start(let interval?) = cmd else {
            Issue.record("expected .start(interval), got \(cmd)")
            return
        }
        #expect(abs(interval - 8 * 3600) < 1)
        #expect(interval > 0)
    }

    @Test func startWithUnparseableInputIsRejected() {
        #expect(parse("sharingan://start?input=zzz") == nil)
    }

    // MARK: - simple hosts

    @Test func simpleCommandHosts() {
        #expect(parse("sharingan://pause") == .pause)
        #expect(parse("sharingan://resume") == .resume)
        #expect(parse("sharingan://skip") == .skip)
        #expect(parse("sharingan://reset") == .reset)
        #expect(parse("sharingan://show") == .show)
        #expect(parse("sharingan://toggle-floating") == .toggleFloating)
    }

    @Test func schemeAndHostAreCaseInsensitive() {
        #expect(parse("SHARINGAN://PAUSE") == .pause)
        #expect(parse("Sharingan://Toggle-Floating") == .toggleFloating)
    }

    // MARK: - add-task

    @Test func addTaskDecodesPercentEncoding() {
        #expect(parse("sharingan://add-task?text=ertaga%20p1%20hisobot")
                == .addTask("ertaga p1 hisobot"))
    }

    @Test func addTaskWithEmptyOrMissingTextIsRejected() {
        #expect(parse("sharingan://add-task") == nil)
        #expect(parse("sharingan://add-task?text=") == nil)
        #expect(parse("sharingan://add-task?text=%20%20") == nil)
    }

    // MARK: - rejection

    @Test func wrongSchemeIsRejected() {
        #expect(parse("http://start") == nil)
        #expect(parse("blink://start") == nil)
    }

    @Test func unknownHostIsRejected() {
        #expect(parse("sharingan://explode") == nil)
        #expect(parse("sharingan://") == nil)
    }
}
