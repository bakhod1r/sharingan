import Foundation
import Testing
@testable import SharinganCore

/// The engine's PURE parts only — diff-driven pending changes, the delete
/// rule, modifiedAt stamping, and the merge entry point. Nothing here may
/// require CloudKit, an iCloud account, or a network (CI has none).
///
/// swift-testing rather than XCTest deliberately: these tests drive TaskStore,
/// whose notification scheduling traps in the xctest runner process (it has a
/// bundle id but no bundle proxy); the swift-testing process has no bundle id,
/// so NotificationService's guard degrades it cleanly.
@MainActor
@Suite("CloudSyncEngine (pure parts)")
struct CloudSyncEngineTests {
    private func tempStore() -> TaskStore {
        TaskStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-syncengine-\(UUID().uuidString).sqlite"))
    }

    // MARK: - pendingChanges

    @Test func pendingChangesAreEmptyWhenNothingChangedSinceLastSync() {
        let store = tempStore()
        store.add(title: "a")
        let shadow = CloudSyncEngine.shadowSnapshot(of: store)   // as if all synced
        #expect(CloudSyncEngine.pendingChanges(tasks: store.tasks, shadow: shadow).isEmpty)
    }

    @Test func editingOneTaskOfManyPushesOnlyThatOne() {
        let store = tempStore()
        for i in 0..<50 { store.add(title: "task \(i)") }
        let shadow = CloudSyncEngine.shadowSnapshot(of: store)
        var edited = store.tasks[7]
        edited.title = "edited"
        store.update(edited)

        let pending = CloudSyncEngine.pendingChanges(tasks: store.tasks, shadow: shadow)
        #expect(pending.count == 1,
                "a whole-collection rewrite must not become a 50-record upload")
        #expect(pending.first?.recordName == edited.recordName)
    }

    @Test func deletedTaskProducesADeletionNotACreation() {
        let store = tempStore()
        store.add(title: "doomed")
        let shadow = CloudSyncEngine.shadowSnapshot(of: store)
        let name = store.tasks[0].recordName
        store.delete(store.tasks[0].id)

        let diff = SyncShadow.diff(local: store.tasks, shadow: shadow)
        #expect(diff.deletedRecordNames == [name])
        #expect(diff.created.isEmpty)
        #expect(diff.changed.isEmpty)
    }

    // MARK: - Remote-delete rule

    @Test func remoteDeleteAppliesToAnUneditedRecord() {
        #expect(CloudSyncEngine.shouldApplyRemoteDelete(localHash: "h1",
                                                        lastSyncedHash: "h1"))
    }

    // Edited since the last confirmed sync → the edit is newer information
    // than the tombstone; the record is kept and re-uploaded.
    @Test func remoteDeleteLosesToAnUnsyncedLocalEdit() {
        #expect(!CloudSyncEngine.shouldApplyRemoteDelete(localHash: "h2",
                                                         lastSyncedHash: "h1"))
    }

    @Test func remoteDeleteOfAnUnknownRecordIsANoOpApply() {
        #expect(CloudSyncEngine.shouldApplyRemoteDelete(localHash: nil,
                                                        lastSyncedHash: "h1"))
    }

    // MARK: - modifiedAt stamping (the persistence-funnel seam)

    @Test func contentEditBumpsModifiedAt() {
        let store = tempStore()
        store.add(title: "a")
        let before = store.tasks[0].modifiedAt
        // The stamp is wall-clock; make sure the edit lands on a later instant.
        Thread.sleep(forTimeInterval: 0.01)
        store.setNotes(store.tasks[0].id, "edited")
        #expect(store.tasks[0].modifiedAt > before)
    }

    @Test func untouchedSiblingsKeepTheirModifiedAt() {
        let store = tempStore()
        store.add(title: "a")
        store.add(title: "b")
        let untouched = store.tasks[1]
        Thread.sleep(forTimeInterval: 0.01)
        store.setNotes(store.tasks[0].id, "edited")
        #expect(store.tasks[1].modifiedAt == untouched.modifiedAt,
                "a DELETE-all + re-INSERT save must not re-stamp every row")
    }

    // MARK: - mergeRemote

    @Test func newerRemoteEditWinsAndDoesNotBounceBackToSync() {
        let store = tempStore()
        store.add(title: "local title")
        var remote = store.tasks[0]
        remote.title = "remote title"
        remote.modifiedAt = store.tasks[0].modifiedAt.addingTimeInterval(60)

        var didPersistFired = false
        store.didPersist = { didPersistFired = true }
        store.mergeRemote(tasks: [remote])

        #expect(store.tasks[0].title == "remote title")
        #expect(!didPersistFired,
                "an applied fetch must not echo straight back to CloudKit")
    }

    @Test func olderRemoteEditLosesToTheLocalCopy() {
        let store = tempStore()
        store.add(title: "local title")
        var remote = store.tasks[0]
        remote.title = "remote title"
        remote.modifiedAt = store.tasks[0].modifiedAt.addingTimeInterval(-60)

        store.mergeRemote(tasks: [remote])
        #expect(store.tasks[0].title == "local title")
    }

    @Test func mergedRemoteTaskKeepsItsOwnModifiedAt() {
        let store = tempStore()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        var remote = TaskItem(title: "from the other Mac")
        remote.modifiedAt = stamp

        store.mergeRemote(tasks: [remote])
        #expect(store.tasks.first { $0.id == remote.id }?.modifiedAt == stamp,
                "re-stamping on merge would turn LWW into last-fetched-wins")
    }

    @Test func mergeRemoteAppliesDeletions() {
        let store = tempStore()
        store.add(title: "doomed")
        let id = store.tasks[0].id
        store.mergeRemote(deletedTaskIDs: [id])
        #expect(store.tasks.isEmpty)
    }

    @Test func focusLogMergesAdditivelyByRecordName() {
        let store = tempStore()
        store.add(title: "t")
        let id = store.tasks[0].id
        store.incrementPomodoro(id, seconds: 900)   // local: count 1, 900 s

        let localRow = store.focusLog[0]
        let remote = FocusLogEntry(day: localRow.day, taskID: id, subtaskID: nil,
                                   title: "t", count: 3, seconds: 600)
        store.mergeRemote(focusEntries: [remote])

        let merged = store.focusLog.first { $0.recordName == localRow.recordName }
        #expect(merged?.count == 3)
        #expect(merged?.seconds == 900)
        #expect(store.focusLog.count == 1, "same triple must merge, never fork")
    }

    // MARK: - didPersist hook

    @Test func localMutationFiresDidPersist() {
        let store = tempStore()
        var fired = 0
        store.didPersist = { fired += 1 }
        store.add(title: "a")
        #expect(fired == 1)
    }
}
