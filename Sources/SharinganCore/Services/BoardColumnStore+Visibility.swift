import Foundation


public extension Array where Element == BoardColumn {
    /// Number of hidden columns (shown as "(N hidden)" in the Columns menu).
    var hiddenCount: Int { filter { !$0.isEnabled }.count }
    /// All columns in display order, hidden ones included (Columns menu rows).
    var inDisplayOrder: [BoardColumn] { sorted { $0.order < $1.order } }
}

public extension BoardColumnStore {
    /// Re-enables every hidden column.
    func showAll() {
        for c in columns where !c.isEnabled { setEnabled(c.id, true) }
    }
}
