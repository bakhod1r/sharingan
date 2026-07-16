import Foundation

// Quick-add by issue key: typing `jira SHRGN-5` into the composer should bring
// the real issue down, linked, rather than leave a local task named after the
// command. `TaskInputParser` spots the form; this turns the key into a task.

extension JiraService {

    /// Imports one Jira issue by key and links it as a local task.
    ///
    /// Deliberately routed through `syncAssignedIssues(jql:)` rather than a
    /// direct `getIssue`: that path already does the whole job — hierarchy
    /// nesting, the last-seen cache snapshot, merge-on-reimport, flat-twin
    /// absorption — and a second, simpler import path would drift from it. The
    /// explicit JQL replaces the `assignee = currentUser()` filter entirely, so
    /// an issue assigned to someone else (or to nobody) imports the same way;
    /// the only requirement is that the account can browse it.
    ///
    /// Re-importing a key already on the board is a no-op merge, not a
    /// duplicate, so this is safe to call twice.
    ///
    /// - Returns: whether the key resolved to an issue that is now linked. False
    ///   when disconnected, when the fetch failed, or when the key matches
    ///   nothing the account can see — inspect `lastSync` / `lastErrorMessage`
    ///   for which.
    @discardableResult
    public func importIssue(key rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return false }

        // Quoted: keys are `[A-Z][A-Z0-9]+-\d+` so this can't inject, and the
        // quotes keep Jira from reading the key as a bare word.
        let summary = await syncAssignedIssues(jql: "key = \"\(key)\"")
        guard !summary.failed else { return false }
        if summary.imported + summary.updated == 0 {
            // 200 + nothing: the key is well-formed but no issue by that key is
            // visible to this account. syncAssignedIssues leaves no message on a
            // successful-but-empty run, so say why here.
            setLastError("No Jira issue \(key) you can see.")
            return false
        }
        return true
    }
}
