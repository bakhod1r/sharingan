import Foundation
import Combine

/// An ordered list of task ids the user plans to focus on, worked through one
/// pomodoro at a time: each completed focus session hands the active slot to
/// the next queued task (see `SharinganCoordinator.advanceQueueAfterFocus`).
///
/// The queue stores only ids — the tasks themselves live in `TaskStore` — so
/// entries can go stale (task deleted or completed elsewhere). Reads that
/// matter (`current` / `advance`) therefore validate against the store and
/// silently drop stale leading entries. Persists to UserDefaults on every
/// mutation.
@MainActor
public final class FocusQueue: ObservableObject {
    /// UserDefaults key: the queue as an array of uuid strings.
    public static let defaultsKey = "sharingan.focusQueue"

    @Published public private(set) var taskIDs: [UUID] = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        taskIDs = (defaults.stringArray(forKey: Self.defaultsKey) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    // MARK: - Mutations

    /// Appends a task to the back of the queue. Ignores duplicates.
    public func enqueue(_ id: UUID) {
        guard !taskIDs.contains(id) else { return }
        taskIDs.append(id)
        persist()
    }

    public func remove(_ id: UUID) {
        guard taskIDs.contains(id) else { return }
        taskIDs.removeAll { $0 == id }
        persist()
    }

    /// Applies a drag reorder (`onMove`).
    public func move(from source: IndexSet, to destination: Int) {
        taskIDs.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    public func clear() {
        guard !taskIDs.isEmpty else { return }
        taskIDs.removeAll()
        persist()
    }

    // MARK: - Validated reads

    /// The task the queue points at right now: the first id that still exists
    /// in the store and isn't done. Stale/done leading entries are dropped
    /// (and the drop persisted) on the way.
    public func current(validatedAgainst store: TaskStore) -> UUID? {
        var dropped = false
        while let head = taskIDs.first {
            if let task = store.tasks.first(where: { $0.id == head }), !task.isDone {
                break
            }
            taskIDs.removeFirst()
            dropped = true
        }
        if dropped { persist() }
        return taskIDs.first
    }

    /// Drops the current (validated) head and returns the next valid id, if any.
    @discardableResult
    public func advance(validatedAgainst store: TaskStore) -> UUID? {
        guard current(validatedAgainst: store) != nil else { return nil }
        taskIDs.removeFirst()
        persist()
        return current(validatedAgainst: store)
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(taskIDs.map(\.uuidString), forKey: Self.defaultsKey)
    }
}
