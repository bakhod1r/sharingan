import Testing
@testable import SharinganCore

@Suite("Sharingan evolution chain — per-eye start")
struct ReviewEvolutionChainTests {
    @Test func sharedStyleStartsAtHeadLikeBefore() {
        for base in [SharinganStyle.classic, .rinnegan] {
            #expect(SharinganEvolutionChain.style(base: base, eyesDiffer: false, count: 0) == .tomoe1)
            #expect(SharinganEvolutionChain.style(base: base, eyesDiffer: false, count: 2) == .classic)
        }
    }

    @Test func differingEyesWalkFromOwnBase() {
        #expect(SharinganEvolutionChain.eyesDiffer(left: .classic, right: .mangekyou))
        #expect(SharinganEvolutionChain.style(base: .classic, eyesDiffer: true, count: 0) == .classic)
        #expect(SharinganEvolutionChain.style(base: .mangekyou, eyesDiffer: true, count: 0) == .mangekyou)
        #expect(SharinganEvolutionChain.style(base: .classic, eyesDiffer: true, count: 1) == .mangekyou)
    }

    @Test func wrapsAroundTheChain() {
        let n = SharinganEvolutionChain.chain.count
        #expect(SharinganEvolutionChain.style(base: .rinnegan, eyesDiffer: true, count: 1) == .tomoe1)
        #expect(SharinganEvolutionChain.style(base: .tomoe1, eyesDiffer: true, count: n) == .tomoe1)
    }
}
