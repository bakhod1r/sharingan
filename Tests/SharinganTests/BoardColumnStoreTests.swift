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
        #expect(store.columns.map(\.name) == ["Today", "This Week", "In Progress", "Paused", "Done", "Cancelled"])
        // Persisted, so a second store over the same defaults reads them back.
        #expect(d.string(forKey: BoardColumnStore.defaultsKey) != nil)
        let reopened = BoardColumnStore(defaults: d)
        #expect(reopened.columns.count == 6)
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
        store.rename(BoardColumn.Seed.paused, to: "On Hold")
        #expect(store.columns.first { $0.id == BoardColumn.Seed.paused }?.name == "On Hold")

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

    @Test("move reorders columns and reload re-reads persisted state")
    func moveAndReload() {
        let (store, d) = freshStore("move")
        // Move "This Week" (order 1) left, ahead of "Today".
        store.move(BoardColumn.Seed.thisWeek, by: -1)
        #expect(store.enabled.first?.id == BoardColumn.Seed.thisWeek)
        // A separate store reading the same defaults sees the new order.
        let other = BoardColumnStore(defaults: d)
        #expect(other.enabled.first?.id == BoardColumn.Seed.thisWeek)
    }
}
