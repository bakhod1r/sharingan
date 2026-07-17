import Foundation
import Testing
@testable import SharinganCore

@MainActor
@Suite("Board column store")
struct BoardColumnStoreTests {

    private func freshStore(_ name: String) -> (BoardColumnStore, UserDefaults) {
        let suite = "BoardColumnStoreTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return (BoardColumnStore(defaults: d), d)
    }

    @Test("a fresh store seeds the six defaults and persists them")
    func seedsDefaults() {
        let (store, d) = freshStore("seed")
        #expect(store.columns.map(\.id) == BoardColumn.defaults.map(\.id))
        // Persisted, so a second store over the same defaults reads them back.
        #expect(d.string(forKey: BoardColumnStore.defaultsKey) != nil)
        let reopened = BoardColumnStore(defaults: d)
        #expect(reopened.columns.count == 8)
    }

    @Test("adding a column appends it enabled at the end")
    func addColumn() {
        let (store, _) = freshStore("add")
        let id = store.addColumn(name: "Blocked")
        #expect(store.columns.last?.id == id)
        #expect(store.columns.last?.name == "Blocked")
        #expect(store.columns.last?.isEnabled == true)
        #expect(store.enabled.last?.id == id)
    }

    @Test("rename, disable and delete take effect")
    func editColumns() {
        let (store, _) = freshStore("edit")
        store.rename(BoardColumn.Seed.onHold, to: "Blocked")
        #expect(store.columns.first { $0.id == BoardColumn.Seed.onHold }?.name == "Blocked")

        store.setEnabled(BoardColumn.Seed.cancelled, false)
        #expect(!store.enabled.contains { $0.id == BoardColumn.Seed.cancelled })

        store.delete(BoardColumn.Seed.today)
        #expect(!store.columns.contains { $0.id == BoardColumn.Seed.today })
    }

    @Test("doneColumnID points at the built-in Done column, and follows disable")
    func doneColumn() {
        let (store, _) = freshStore("done")
        #expect(store.doneColumnID == BoardColumn.Seed.done)
        store.setEnabled(BoardColumn.Seed.done, false)
        #expect(store.doneColumnID == nil)
    }

    @Test("moveColumn drops a column into another's slot")
    func moveColumnToSlot() {
        let (store, _) = freshStore("moveTo")
        // Move Archived (last) into Inbox's slot (first).
        store.moveColumn(BoardColumn.Seed.archived, toSlotOf: BoardColumn.Seed.inbox)
        #expect(store.enabled.first?.id == BoardColumn.Seed.archived)
        #expect(store.enabled.map(\.id) == [
            BoardColumn.Seed.archived, BoardColumn.Seed.inbox, BoardColumn.Seed.today,
            BoardColumn.Seed.thisWeek, BoardColumn.Seed.inProgress, BoardColumn.Seed.onHold,
            BoardColumn.Seed.done, BoardColumn.Seed.cancelled,
        ])
    }

    @Test("moveColumn onto itself or an unknown id is a no-op")
    func moveColumnNoop() {
        let (store, _) = freshStore("moveNoop")
        let before = store.enabled.map(\.id)
        store.moveColumn(BoardColumn.Seed.today, toSlotOf: BoardColumn.Seed.today)
        store.moveColumn(BoardColumn.Seed.today, toSlotOf: "ghost")
        #expect(store.enabled.map(\.id) == before)
    }

    @Test("move reorders columns and reload re-reads persisted state")
    func moveAndReload() {
        let (store, d) = freshStore("move")
        // Move "Today" (order 1) left, ahead of "Inbox".
        store.move(BoardColumn.Seed.today, by: -1)
        #expect(store.enabled.first?.id == BoardColumn.Seed.today)
        // A separate store reading the same defaults sees the new order.
        let other = BoardColumnStore(defaults: d)
        #expect(other.enabled.first?.id == BoardColumn.Seed.today)
    }
}
