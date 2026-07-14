import Foundation

/// How two Macs' versions of the same record are reconciled. Every function
/// here is pure — the rules are the part that must never be wrong, so they
/// are tested without CloudKit, an account, or a network.
public enum MergePolicy {
    /// Tasks resolve at record level, newest edit wins. Field-level merging
    /// was rejected deliberately: a task's fields are not independent (a
    /// subtask list and its estimate, a due date and its recurrence), so
    /// interleaving two edits can synthesize a task neither Mac ever had.
    public static func mergeTask(local: TaskItem?, remote: TaskItem) -> TaskItem {
        guard let local else { return remote }
        return remote.modifiedAt > local.modifiedAt ? remote : local
    }

    /// Statistics are append-mostly counters: taking the max per field means
    /// two Macs that each logged part of the same day converge on the larger
    /// truth instead of one erasing the other. It cannot lose focus time —
    /// the worst case is that simultaneous work on both Macs is undercounted
    /// rather than double-counted, which is the safer error.
    public static func mergeFocusLog(local: FocusLogEntry?, remote: FocusLogEntry) -> FocusLogEntry {
        guard let local else { return remote }
        var merged = remote
        merged.count = max(local.count, remote.count)
        merged.seconds = max(local.seconds, remote.seconds)
        merged.title = remote.title.isEmpty ? local.title : remote.title
        return merged
    }

    /// The active timer is one record; whoever wrote last owns the session.
    /// `>=` (unlike tasks' strict `>`): the timer is transient state, and on
    /// an exact tie the remote is at least as fresh as what we hold.
    public static func mergeTimer(local: ActiveTimerState?,
                                  remote: ActiveTimerState) -> ActiveTimerState {
        guard let local else { return remote }
        return remote.updatedAt >= local.updatedAt ? remote : local
    }

    /// A tombstone only wins if nothing edited the record after it was
    /// deleted; otherwise the newer edit is a deliberate resurrection.
    public static func shouldApplyDelete(recordName: String,
                                         local: TaskItem?,
                                         deletedAt: Date) -> Bool {
        guard let local else { return true }
        return deletedAt >= local.modifiedAt
    }
}
