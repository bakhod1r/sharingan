import Testing
import Foundation
@testable import SharinganCore

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite("Break face and eye random")
struct BreakFaceEyeRandomTests {

    private func random(_ f: (inout PomodoroSettings) -> Void = { _ in }) -> PomodoroSettings {
        var s = PomodoroSettings()
        s.breakFaceEyeMode = .random
        f(&s)
        return s
    }

    @Test("defaults")
    func defaults() {
        let s = PomodoroSettings()
        #expect(s.breakFaceEyeMode == .fixed)
        #expect(s.breakRandomFaces == BreakEyeShape.allCases)
        #expect(s.breakRandomEyes == [.original, .sharingan(.classic), .sharingan(.mangekyou), .sharingan(.rinnegan)])
        #expect(s.breakRandomChange == .eachBreak)
        #expect(s.breakRandomPairing == .same)
    }

    @Test("legacy JSON decodes to defaults")
    func legacy() throws {
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: Data("{\"sharinganStyle\":\"classic\"}".utf8))
        #expect(s.breakFaceEyeMode == .fixed)
        #expect(s.breakRandomFaces == BreakEyeShape.allCases)
        #expect(s.breakRandomEyes.count == 4)
    }

    @Test("round trip of all new keys")
    func roundTrip() throws {
        var s = PomodoroSettings()
        s.breakFaceEyeMode = .random
        s.breakRandomFaces = [.angry]
        s.breakRandomEyes = [.original, .sharingan(.itachi)]
        s.breakRandomChange = .eachStep
        s.breakRandomPairing = .separate
        let b = try JSONDecoder().decode(PomodoroSettings.self, from: JSONEncoder().encode(s))
        #expect(b.breakFaceEyeMode == .random)
        #expect(b.breakRandomFaces == [.angry])
        #expect(b.breakRandomEyes == [.original, .sharingan(.itachi)])
        #expect(b.breakRandomChange == .eachStep)
        #expect(b.breakRandomPairing == .separate)
    }

    @Test("eye choice encodes as a single string")
    func choiceEncoding() throws {
        let d = try JSONEncoder().encode([BreakEyeChoice.original, .sharingan(.rinnegan)])
        #expect(String(data: d, encoding: .utf8) == "[\"original\",\"rinnegan\"]")
    }

    @Test("pool decoding drops unknown strings")
    func dropsUnknown() throws {
        let json = "{\"breakRandomEyes\":[\"original\",\"bogus\",\"rinnegan\"],\"breakRandomFaces\":[\"angry\",\"nope\"]}"
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: Data(json.utf8))
        #expect(s.breakRandomEyes == [.original, .sharingan(.rinnegan)])
        #expect(s.breakRandomFaces == [.angry])
    }

    @Test("fixed mode returns the fixed look")
    func fixedPassthrough() {
        var s = PomodoroSettings()
        s.breakEyeShape = .angry
        s.breakIrisStyle = .original
        s.sharinganStyle = .itachi
        s.sharinganStyleRight = .rinnegan
        var rng = SeededRNG(1)
        let l = BreakFaceEyeRandomizer.look(settings: s, previous: nil, using: &rng)
        #expect(l == BreakLook(face: .angry, iris: .original, leftStyle: .itachi, rightStyle: .rinnegan))
    }

    @Test("only pool members are returned")
    func poolMembers() {
        let s = random { $0.breakRandomFaces = [.angry, .lookingFor]
                         $0.breakRandomEyes = [.original, .sharingan(.mangekyou)] }
        var rng = SeededRNG(7)
        var prev: BreakLook?
        var faces = Set<BreakEyeShape>()
        for _ in 0..<500 {
            let l = BreakFaceEyeRandomizer.look(settings: s, previous: prev, using: &rng)
            #expect([.angry, .lookingFor].contains(l.face))
            if l.iris == .sharingan { #expect(l.leftStyle == .mangekyou) }
            faces.insert(l.face)
            prev = l
        }
        #expect(faces.count == 2)
    }

    @Test("no immediate repeat when more than one look exists")
    func noRepeat() {
        let s = random { $0.breakRandomFaces = [.sharingan]
                         $0.breakRandomEyes = [.original, .sharingan(.classic)] }
        var rng = SeededRNG(3)
        var prev: BreakLook?
        for _ in 0..<300 {
            let l = BreakFaceEyeRandomizer.look(settings: s, previous: prev, using: &rng)
            #expect(l != prev)
            prev = l
        }
    }

    @Test("a single combination may repeat")
    func singleCombo() {
        let s = random { $0.breakRandomFaces = [.angry]; $0.breakRandomEyes = [.original] }
        var rng = SeededRNG(3)
        let a = BreakFaceEyeRandomizer.look(settings: s, previous: nil, using: &rng)
        let b = BreakFaceEyeRandomizer.look(settings: s, previous: a, using: &rng)
        #expect(a == b)
    }

    @Test("empty pools fall back to the fixed look")
    func emptyPool() {
        var rng = SeededRNG(5)
        let noFaces = random { $0.breakRandomFaces = []; $0.breakEyeShape = .angry }
        #expect(BreakFaceEyeRandomizer.look(settings: noFaces, previous: nil, using: &rng).face == .angry)
        let noEyes = random { $0.breakRandomEyes = []; $0.breakIrisStyle = .original }
        #expect(BreakFaceEyeRandomizer.look(settings: noEyes, previous: nil, using: &rng).iris == .original)
        let cur = BreakFaceEyeRandomizer.fixedLook(noEyes)
        #expect(BreakFaceEyeRandomizer.eyesOnly(settings: noEyes, current: cur, using: &rng) == cur)
    }

    @Test("same pairing leaves the right eye mirroring the left")
    func samePairing() {
        let s = random { $0.breakRandomPairing = .same }
        var rng = SeededRNG(11)
        for _ in 0..<200 {
            #expect(BreakFaceEyeRandomizer.look(settings: s, previous: nil, using: &rng).rightStyle == nil)
        }
    }

    @Test("separate pairing can differ, and never mixes iris kinds")
    func separatePairing() {
        let s = random { $0.breakRandomPairing = .separate
                         $0.breakRandomEyes = [.original, .sharingan(.classic), .sharingan(.rinnegan)] }
        var rng = SeededRNG(13)
        var differed = false
        for _ in 0..<500 {
            let l = BreakFaceEyeRandomizer.look(settings: s, previous: nil, using: &rng)
            if l.iris == .sharingan {
                #expect([.classic, .rinnegan].contains(l.leftStyle))
                #expect([.classic, .rinnegan].contains(l.rightStyle ?? .tomoe1))
                if l.rightStyle != l.leftStyle { differed = true }
            }
        }
        #expect(differed)
    }

    @Test("separate with one original and one sharingan never mixes")
    func separateNoMix() {
        let s = random { $0.breakRandomPairing = .separate
                         $0.breakRandomEyes = [.original, .sharingan(.classic)] }
        var rng = SeededRNG(17)
        for _ in 0..<200 {
            let l = BreakFaceEyeRandomizer.look(settings: s, previous: nil, using: &rng)
            if l.iris == .sharingan { #expect(l.rightStyle == .classic) }
        }
    }

    @Test("eachStep keeps the face and changes only the eyes")
    func eyesOnlyKeepsFace() {
        let s = random { $0.breakRandomEyes = [.original, .sharingan(.classic), .sharingan(.itachi)] }
        var rng = SeededRNG(19)
        var cur = BreakLook(face: .lookingFor, iris: .original, leftStyle: .classic, rightStyle: nil)
        for _ in 0..<300 {
            let n = BreakFaceEyeRandomizer.eyesOnly(settings: s, current: cur, using: &rng)
            #expect(n.face == .lookingFor)
            #expect(n != cur)
            cur = n
        }
    }
}
