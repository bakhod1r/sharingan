import Foundation
import Combine

/// Owns the Sharingan board's column list. Persisted as JSON under the
/// `board.columns` UserDefaults key, which `SettingsSync` mirrors across Macs;
/// a task names its column through `TaskItem.boardColumnID`.
///
/// Deliberately separate from `TaskStore`: the board view observes both, and
/// column CRUD stays independent of the task list.
@MainActor
public final class BoardColumnStore: ObservableObject {
    public static let shared = BoardColumnStore()

    /// UserDefaults key — also on `SettingsSync.syncedKeys`.
    public static let defaultsKey = "board.columns"

    @Published public private(set) var columns: [BoardColumn]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.columns = Self.load(from: defaults) ?? BoardColumn.defaults
        if Self.load(from: defaults) == nil { persist() }   // seed on first run
    }

    // MARK: - Derived

    /// Enabled columns in display order — what the board renders.
    public var enabled: [BoardColumn] { columns.enabledInOrder }

    /// The id of the built-in Done column, if one is still present & enabled.
    public var doneColumnID: String? {
        enabled.first { $0.role == .done }?.id
    }

    /// The column a task with this stored id renders in (fallback-aware).
    public func resolvedColumn(for storedID: String?) -> BoardColumn? {
        columns.resolvedColumn(for: storedID)
    }

    // MARK: - Mutations

    /// Adds an enabled `.plain` column at the end. Returns its id.
    @discardableResult
    public func addColumn(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let col = BoardColumn(name: trimmed.isEmpty ? "New column" : trimmed,
                              order: (columns.map(\.order).max() ?? -1) + 1)
        columns.append(col)
        persist()
        return col.id
    }

    public func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[i].name = trimmed
        persist()
    }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        guard let i = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[i].isEnabled = enabled
        persist()
    }

    /// Removes a column. Tasks that named it keep the id and fall back to the
    /// first enabled column on render, so no task is lost.
    public func delete(_ id: String) {
        columns.removeAll { $0.id == id }
        persist()
    }

    /// Drag-reorder: drops the column `id` into `targetID`'s slot, shifting the
    /// rest. No-op if either is unknown or they're the same.
    public func moveColumn(_ id: String, toSlotOf targetID: String) {
        guard id != targetID else { return }
        var ordered = columns.sorted { $0.order < $1.order }
        guard let from = ordered.firstIndex(where: { $0.id == id }),
              let to = ordered.firstIndex(where: { $0.id == targetID }) else { return }
        let moved = ordered.remove(at: from)
        ordered.insert(moved, at: to)
        for (index, col) in ordered.enumerated() {
            if let i = columns.firstIndex(where: { $0.id == col.id }) { columns[i].order = index }
        }
        persist()
    }

    /// Moves a column one step left/right in display order.
    public func move(_ id: String, by delta: Int) {
        let ordered = columns.sorted { $0.order < $1.order }
        guard let pos = ordered.firstIndex(where: { $0.id == id }) else { return }
        let target = pos + delta
        guard ordered.indices.contains(target) else { return }
        var reordered = ordered
        reordered.swapAt(pos, target)
        for (index, var col) in reordered.enumerated() {
            col.order = index
            if let i = columns.firstIndex(where: { $0.id == col.id }) { columns[i].order = index }
        }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(columns),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> [BoardColumn]? {
        guard let json = defaults.string(forKey: defaultsKey),
              let data = json.data(using: .utf8),
              let cols = try? JSONDecoder().decode([BoardColumn].self, from: data),
              !cols.isEmpty else { return nil }
        return cols
    }

    /// Re-read the persisted list (e.g. after a remote settings-sync apply).
    public func reload() {
        if let cols = Self.load(from: defaults) { columns = cols }
    }
}
