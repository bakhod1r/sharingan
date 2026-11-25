import Testing
import Foundation
@testable import SharinganCore

@Suite("Break eye shape settings")
struct BreakEyeShapeSettingsTests {

    @Test("defaults keep the Sharingan eye and Sharingan iris")
    func defaults() {
        let s = PomodoroSettings()
        #expect(s.breakEyeShape == .sharingan)
        #expect(s.breakIrisStyle == .sharingan)
    }

    @Test("legacy JSON without the keys decodes to defaults")
    func legacyDecode() throws {
        let data = Data("{\"sharinganStyle\":\"classic\"}".utf8)
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: data)
        #expect(s.breakEyeShape == .sharingan)
        #expect(s.breakIrisStyle == .sharingan)
    }

    @Test("unknown raw values fall back to defaults instead of dropping the blob")
    func unknownRaw() throws {
        let data = Data("{\"breakEyeShape\":\"future\",\"breakIrisStyle\":\"future\",\"breakPatternMixed\":true}".utf8)
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: data)
        #expect(s.breakEyeShape == .sharingan)
        #expect(s.breakIrisStyle == .sharingan)
        #expect(s.breakPatternMixed == true)
    }

    @Test("round trip keeps the choice")
    func roundTrip() throws {
        var s = PomodoroSettings()
        s.breakEyeShape = .lookingFor
        s.breakIrisStyle = .original
        let back = try JSONDecoder().decode(PomodoroSettings.self, from: JSONEncoder().encode(s))
        #expect(back.breakEyeShape == .lookingFor)
        #expect(back.breakIrisStyle == .original)
    }

    @Test("labels and ids")
    func labels() {
        #expect(BreakEyeShape.allCases.map(\.label) == ["Sharingan", "Looking-for", "Angry"])
        #expect(BreakIrisStyle.allCases.map(\.label) == ["Sharingan", "Original"])
        #expect(BreakEyeShape.lookingFor.id == "lookingFor")
        #expect(BreakEyeShape.angry.label == "Angry")
    }

    @Test("iris style defaults to Sharingan")
    func irisDefault() {
        #expect(BreakIrisStyle.allCases.first == .sharingan)
        #expect(PomodoroSettings().breakIrisStyle == .sharingan)
    }

    @Test("all 3x2 face and eye combinations round-trip")
    func allCombinations() throws {
        #expect(BreakEyeShape.allCases.count == 3)
        for face in BreakEyeShape.allCases {
            for eye in BreakIrisStyle.allCases {
                var s = PomodoroSettings()
                s.breakEyeShape = face
                s.breakIrisStyle = eye
                let back = try JSONDecoder().decode(PomodoroSettings.self, from: JSONEncoder().encode(s))
                #expect(back.breakEyeShape == face)
                #expect(back.breakIrisStyle == eye)
            }
        }
    }

    @Test("angry raw value is stable and legacy JSON never decodes to it")
    func angryRaw() throws {
        #expect(BreakEyeShape.angry.rawValue == "angry")
        let data = Data("{\"breakEyeShape\":\"angry\"}".utf8)
        #expect(try JSONDecoder().decode(PomodoroSettings.self, from: data).breakEyeShape == .angry)
        let legacy = Data("{\"sharinganStyle\":\"classic\"}".utf8)
        #expect(try JSONDecoder().decode(PomodoroSettings.self, from: legacy).breakEyeShape == .sharingan)
    }
}
