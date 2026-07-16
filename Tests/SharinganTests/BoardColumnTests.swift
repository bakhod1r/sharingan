import Foundation
import Testing
@testable import SharinganCore

@Suite("Board columns")
struct BoardColumnTests {

    @Test("default seed is the six columns in order, Done is the only .done role")
    func defaultSeed() {
        let d = BoardColumn.defaults
        #expect(d.map(\.name) == ["Today", "This Week", "In Progress", "Paused", "Done", "Cancelled"])
        #expect(d.map(\.order) == [0, 1, 2, 3, 4, 5])
        #expect(d.filter { $0.role == .done }.map(\.id) == [BoardColumn.Seed.done])
        #expect(d.filter { !$0.isEnabled }.isEmpty)
    }

    @Test("a column round-trips through Codable")
    func codableRoundTrip() throws {
        let col = BoardColumn(id: "x", name: "Blocked", order: 7, isEnabled: false, role: .plain)
        let data = try JSONEncoder().encode(col)
        let back = try JSONDecoder().decode(BoardColumn.self, from: data)
        #expect(back == col)
    }

    @Test("older rows missing new keys decode with defaults")
    func lenientDecode() throws {
        let json = #"{"id":"y","name":"Legacy"}"#.data(using: .utf8)!
        let col = try JSONDecoder().decode(BoardColumn.self, from: json)
        #expect(col.order == 0)
        #expect(col.isEnabled == true)
        #expect(col.role == .plain)
    }

    @Test("migration sends done tasks to Done, open tasks to nil")
    func migration() {
        #expect(BoardColumn.migratedColumnID(isDone: true) == BoardColumn.Seed.done)
        #expect(BoardColumn.migratedColumnID(isDone: false) == nil)
    }

    @Test("enabledInOrder drops disabled columns and sorts by order")
    func enabledInOrder() {
        let cols = [
            BoardColumn(id: "b", name: "B", order: 2),
            BoardColumn(id: "a", name: "A", order: 0),
            BoardColumn(id: "c", name: "C", order: 1, isEnabled: false),
        ]
        #expect(cols.enabledInOrder.map(\.id) == ["a", "b"])
    }

    @Test("a task in a disabled or unknown column falls back to the first enabled column")
    func fallbackResolution() {
        let cols = BoardColumn.defaults
        // A real, enabled id resolves to itself.
        #expect(cols.resolvedColumn(for: BoardColumn.Seed.inProgress)?.id == BoardColumn.Seed.inProgress)
        // nil / unknown fall back to the first column (Today).
        #expect(cols.resolvedColumn(for: nil)?.id == BoardColumn.Seed.today)
        #expect(cols.resolvedColumn(for: "deleted-col")?.id == BoardColumn.Seed.today)
    }

    @Test("with the first column disabled, fallback is the next enabled one")
    func fallbackSkipsDisabledFirst() {
        var cols = BoardColumn.defaults
        cols[0].isEnabled = false          // disable Today
        #expect(cols.resolvedColumn(for: nil)?.id == BoardColumn.Seed.thisWeek)
    }
}
