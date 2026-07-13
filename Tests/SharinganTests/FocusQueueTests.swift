import Foundation
import Testing
@testable import SharinganCore

@MainActor
@Suite("Focus queue")
struct FocusQueueTests {
    private func tempStore() -> TaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-fq-\(UUID().uuidString).sqlite")
        return TaskStore(fileURL: url)
    }

    /// Isolated defaults so tests never touch the real "sharingan.focusQueue" key.
    private func tempDefaults() -> (defaults: UserDefaults, name: String) {
        let name = "blink-fq-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    // MARK: - Basic mutations

    @Test func enqueueDedupes() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let q = FocusQueue(defaults: defaults)
        let a = UUID(), b = UUID()
        q.enqueue(a)
        q.enqueue(b)
        q.enqueue(a)   // duplicate — ignored
        #expect(q.taskIDs == [a, b])
    }

    @Test func removeAndClear() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let q = FocusQueue(defaults: defaults)
        let a = UUID(), b = UUID(), c = UUID()
        q.enqueue(a); q.enqueue(b); q.enqueue(c)

        q.remove(b)
        #expect(q.taskIDs == [a, c])

        q.clear()
        #expect(q.taskIDs.isEmpty)
    }

    @Test func moveReorders() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let q = FocusQueue(defaults: defaults)
        let a = UUID(), b = UUID(), c = UUID()
        q.enqueue(a); q.enqueue(b); q.enqueue(c)

        q.move(from: IndexSet(integer: 2), to: 0)
        #expect(q.taskIDs == [c, a, b])
    }

    // MARK: - Persistence

    @Test func persistsAcrossInstances() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let a = UUID(), b = UUID()

        let first = FocusQueue(defaults: defaults)
        first.enqueue(a)
        first.enqueue(b)

        let second = FocusQueue(defaults: defaults)
        #expect(second.taskIDs == [a, b])

        second.remove(a)
        let third = FocusQueue(defaults: defaults)
        #expect(third.taskIDs == [b])
    }

    @Test func ignoresGarbageInDefaults() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["not-a-uuid", UUID().uuidString], forKey: FocusQueue.defaultsKey)
        let q = FocusQueue(defaults: defaults)
        #expect(q.taskIDs.count == 1)   // the bad entry is dropped
    }

    // MARK: - Validation against the store

    @Test func currentSkipsStaleAndDoneEntries() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = tempStore()
        store.add(title: "Done already")
        store.add(title: "Next up")
        let doneID = store.tasks[0].id
        let openID = store.tasks[1].id
        store.toggleDone(doneID)

        let q = FocusQueue(defaults: defaults)
        q.enqueue(UUID())   // ghost — never existed in the store
        q.enqueue(doneID)
        q.enqueue(openID)

        #expect(q.current(validatedAgainst: store) == openID)
        // The stale leading entries were dropped and the drop was persisted.
        #expect(q.taskIDs == [openID])
        #expect(FocusQueue(defaults: defaults).taskIDs == [openID])
    }

    @Test func currentIsNilWhenNothingValid() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = tempStore()
        store.add(title: "Finished")
        let id = store.tasks[0].id
        store.toggleDone(id)

        let q = FocusQueue(defaults: defaults)
        q.enqueue(UUID())
        q.enqueue(id)
        #expect(q.current(validatedAgainst: store) == nil)
        #expect(q.taskIDs.isEmpty)
    }

    @Test func advanceDropsHeadAndReturnsNextValid() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = tempStore()
        store.add(title: "First")
        store.add(title: "Second done")
        store.add(title: "Third")
        let first = store.tasks[0].id
        let secondDone = store.tasks[1].id
        let third = store.tasks[2].id
        store.toggleDone(secondDone)

        let q = FocusQueue(defaults: defaults)
        q.enqueue(first); q.enqueue(secondDone); q.enqueue(third)

        // Drops "First", skips the done "Second", lands on "Third".
        #expect(q.advance(validatedAgainst: store) == third)
        #expect(q.taskIDs == [third])
    }

    @Test func advanceOnEmptyOrFullyStaleQueueReturnsNil() {
        let (defaults, name) = tempDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = tempStore()

        let q = FocusQueue(defaults: defaults)
        #expect(q.advance(validatedAgainst: store) == nil)

        q.enqueue(UUID())   // ghost only
        #expect(q.advance(validatedAgainst: store) == nil)
        #expect(q.taskIDs.isEmpty)
    }
}

@MainActor
@Suite("Focus queue — coordinator wiring")
struct FocusQueueCoordinatorTests {
    private func tempStore() -> TaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-fqc-\(UUID().uuidString).sqlite")
        return TaskStore(fileURL: url)
    }

    /// Coordinator with a queue backed by throwaway defaults, so tests never
    /// touch the real "sharingan.focusQueue" key.
    private func makeCoordinator() -> (SharinganCoordinator, cleanup: () -> Void) {
        let name = "blink-fqc-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let coordinator = SharinganCoordinator(timer: PomodoroTimer(),
                                           focusQueue: FocusQueue(defaults: defaults))
        return (coordinator, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func focusCompletionAdvancesQueueAndActivatesNext() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        store.add(title: "Current")
        store.add(title: "Next")
        let current = store.tasks[0].id
        let next = store.tasks[1].id
        c.focusQueue.enqueue(current)
        c.focusQueue.enqueue(next)
        store.setActive(current)

        c.advanceQueueAfterFocus(store: store)

        #expect(store.activeTaskID == next)
        #expect(c.focusQueue.taskIDs == [next])
    }

    @Test func finishedDoneTaskFallsOutOfQueue() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        store.add(title: "Wrapped up")
        store.add(title: "Next")
        let done = store.tasks[0].id
        let next = store.tasks[1].id
        c.focusQueue.enqueue(done)
        c.focusQueue.enqueue(next)
        store.setActive(done)
        store.toggleDone(done)

        c.advanceQueueAfterFocus(store: store)

        #expect(store.activeTaskID == next)
        #expect(c.focusQueue.taskIDs == [next])
    }

    @Test func activeTaskOutsideQueueIsLeftAlone() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        store.add(title: "Off-queue work")
        store.add(title: "Queued")
        let offQueue = store.tasks[0].id
        let queued = store.tasks[1].id
        c.focusQueue.enqueue(queued)
        store.setActive(offQueue)

        c.advanceQueueAfterFocus(store: store)

        #expect(store.activeTaskID == offQueue)
        #expect(c.focusQueue.taskIDs == [queued])
    }

    @Test func drainedQueueKeepsActiveTask() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        store.add(title: "Last one")
        let last = store.tasks[0].id
        c.focusQueue.enqueue(last)
        store.setActive(last)

        c.advanceQueueAfterFocus(store: store)

        // Queue is drained; the finished task stays active.
        #expect(store.activeTaskID == last)
        #expect(c.focusQueue.taskIDs.isEmpty)
    }

    @Test func breakEndFlagsTaskPickWhenNothingToWorkOn() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        #expect(c.needsTaskPick == false)

        c.evaluateTaskPickAfterBreak(store: store)
        #expect(c.needsTaskPick == true)
    }

    @Test func breakEndDoesNotFlagWhenActiveOpenTaskExists() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        store.add(title: "Still working")
        store.setActive(store.tasks[0].id)

        c.evaluateTaskPickAfterBreak(store: store)
        #expect(c.needsTaskPick == false)
    }

    @Test func breakEndDoesNotFlagWhenQueueHasWork() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        store.add(title: "Queued up")
        c.focusQueue.enqueue(store.tasks[0].id)

        c.evaluateTaskPickAfterBreak(store: store)
        #expect(c.needsTaskPick == false)
    }

    @Test func breakEndClearsAStaleFlag() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        c.evaluateTaskPickAfterBreak(store: store)
        #expect(c.needsTaskPick == true)

        store.add(title: "Picked meanwhile")
        store.setActive(store.tasks[0].id)
        c.evaluateTaskPickAfterBreak(store: store)
        #expect(c.needsTaskPick == false)
    }

    @Test func resolveTaskPickActivatesAndClearsFlag() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        store.add(title: "Chosen")
        let id = store.tasks[0].id
        c.evaluateTaskPickAfterBreak(store: store)
        #expect(c.needsTaskPick == true)

        c.resolveTaskPick(with: id, store: store)
        #expect(store.activeTaskID == id)
        #expect(c.needsTaskPick == false)
    }

    @Test func resolveTaskPickWithNilJustClearsFlag() {
        let (c, cleanup) = makeCoordinator()
        defer { cleanup() }
        let store = tempStore()
        c.evaluateTaskPickAfterBreak(store: store)
        #expect(c.needsTaskPick == true)

        c.resolveTaskPick(with: nil, store: store)
        #expect(store.activeTaskID == nil)
        #expect(c.needsTaskPick == false)
    }
}
