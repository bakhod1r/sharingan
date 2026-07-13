import Foundation
import Testing
@testable import SharinganCore

@MainActor
@Suite("Custom tags (sidebar +)")
struct CustomTagsTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-customtags-\(UUID().uuidString).sqlite")
    }

    private func tempStore() -> TaskStore { TaskStore(fileURL: tempURL()) }

    // MARK: - addCustomTag

    @Test func addTrimsWhitespaceAndStripsLeadingHash() {
        let s = tempStore()
        #expect(s.addCustomTag("  #focus  "))
        #expect(s.customTags == ["focus"])
        #expect(s.allTags == ["focus"])
    }

    @Test func addRejectsEmptyAfterTrim() {
        let s = tempStore()
        #expect(!s.addCustomTag("   "))
        #expect(!s.addCustomTag("#"))
        #expect(s.customTags.isEmpty)
    }

    @Test func addRejectsCaseInsensitiveDuplicateAgainstExistingCustomTag() {
        let s = tempStore()
        #expect(s.addCustomTag("Deep"))
        #expect(!s.addCustomTag("deep"))
        #expect(!s.addCustomTag("DEEP"))
        #expect(s.customTags == ["Deep"])
    }

    @Test func addRejectsCaseInsensitiveDuplicateAgainstTaskDerivedTag() {
        let s = tempStore()
        s.add(title: "Ship it", tags: ["Q3"])
        #expect(!s.addCustomTag("q3"))
        #expect(s.customTags.isEmpty)
    }

    // MARK: - allTags merge order

    @Test func allTagsOrdersUsedByFrequencyThenUnusedCustomsAlphabetically() {
        let s = tempStore()
        s.add(title: "A", tags: ["focus", "deep"])
        s.add(title: "B", tags: ["focus"])
        // "focus" used twice, "deep" used once — both task-derived.
        s.addCustomTag("zeta")
        s.addCustomTag("alpha")
        #expect(s.allTags == ["focus", "deep", "alpha", "zeta"])
    }

    @Test func customTagThatGainsUsesAppearsOnlyOnceViaFrequency() {
        let s = tempStore()
        s.addCustomTag("focus")
        s.add(title: "A", tags: ["focus"])
        #expect(s.allTags == ["focus"])
        #expect(s.allTags.filter { $0 == "focus" }.count == 1)
    }

    // MARK: - removeCustomTag

    @Test func removeCustomTagDropsFromCustomListOnly() {
        let s = tempStore()
        s.addCustomTag("scratch")
        #expect(s.allTags == ["scratch"])
        s.removeCustomTag("scratch")
        #expect(s.customTags.isEmpty)
        #expect(s.allTags.isEmpty)
    }

    @Test func removeCustomTagNeverTouchesTasks() {
        let s = tempStore()
        s.add(title: "A", tags: ["focus"])
        s.addCustomTag("focus") // no-op: dup against task-derived tag
        s.removeCustomTag("focus")
        // The tag is still on the task — removeCustomTag must not call removeTag.
        #expect(s.tasks[0].tags == ["focus"])
        #expect(s.allTags == ["focus"])
    }

    @Test func removeCustomTagIsCaseInsensitive() {
        let s = tempStore()
        s.addCustomTag("Focus")
        s.removeCustomTag("focus")
        #expect(s.customTags.isEmpty)
    }

    // MARK: - persistence

    @Test func customTagsPersistAcrossInstances() {
        let url = tempURL()
        let s = TaskStore(fileURL: url)
        s.addCustomTag("focus")
        s.addCustomTag("deep")

        let reloaded = TaskStore(fileURL: url)
        #expect(Set(reloaded.customTags) == Set(["focus", "deep"]))
    }
}
