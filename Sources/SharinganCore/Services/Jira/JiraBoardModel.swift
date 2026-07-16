import Foundation
import Combine

/// A mini sprint board: the active sprint's cards **assigned to me**, laid out in
/// the board's own columns, with a drag mapped onto a real Jira transition.
///
/// Standalone by design — it takes a `JiraClient` and the site host in its init
/// rather than reaching into `JiraService`, so it stays testable against the same
/// URLProtocol stub the client uses and shares no mutable state with the sync
/// engine. Column membership is decided by **status id**, never by name: the
/// user's workflow (To Do → In Progress → Code review → … → Done) is custom, and
/// names drift while ids don't.
@MainActor
public final class JiraBoardModel: ObservableObject {

    // MARK: - Public surface

    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        /// More than one board matched the project — the user must pick before
        /// there is anything to lay out.
        case chooseBoard
        case loaded
        case error
    }

    /// A single card on the board. Carries exactly what the view draws plus the
    /// status id that decides its column.
    public struct Card: Identifiable, Equatable, Sendable {
        public let id: String            // the Jira key, unique on a board and the drag payload
        public let key: String
        public let summary: String
        public let issueType: String?
        public let priorityName: String?
        public let estimateSeconds: Int?
        /// Nil when the Agile API trimmed the status object — such a card falls
        /// through to the "Other" column rather than pretending to a position.
        public internal(set) var statusId: String?
        /// Jira's status-category key ("new" / "indeterminate" / "done"). Drives
        /// the header's done/remaining split.
        public internal(set) var statusCategoryKey: String?

        public var isDone: Bool { statusCategoryKey == "done" }
    }

    /// A board column: its name, the set of status ids that belong to it, and the
    /// cards currently mapped there.
    public struct Column: Identifiable, Equatable, Sendable {
        public let id: String            // column name, or the sentinel for "Other"
        public let name: String
        public let statusIds: Set<String>
        public var cards: [Card]
        public let isOther: Bool

        static let otherID = "__sharingan_other__"
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var columns: [Column] = []
    @Published public private(set) var sprintName: String?
    /// Populated only when `load` found more than one board; the picker reads it.
    @Published public private(set) var availableBoards: [JiraBoard] = []
    /// The last thing that went wrong — a load failure, or a refused/failed move.
    /// Cleared at the start of the next load or successful move.
    @Published public private(set) var errorMessage: String?

    public let siteHost: String

    private let client: JiraClient
    /// Held so the no-active-sprint fallback can query `project = "KEY"`.
    private var projectKey: String = ""

    public init(client: JiraClient, siteHost: String) {
        self.client = client
        self.siteHost = siteHost
    }

    // MARK: - Load

    /// Loads the board for a project: resolve the board (auto-select if there is
    /// exactly one, otherwise surface the list), read its columns, find the
    /// active sprint, and fill the columns with my cards.
    public func load(projectKey: String) async {
        self.projectKey = projectKey
        phase = .loading
        errorMessage = nil
        availableBoards = []
        columns = []
        sprintName = nil

        do {
            let boards = try await client.getBoards(projectKeyOrId: projectKey)
            switch boards.values.count {
            case 0:
                phase = .error
                errorMessage = "No board found for \(projectKey)."
            case 1:
                await loadBoard(boards.values[0])
            default:
                // Picking one silently would lay out someone else's board, so ask.
                availableBoards = boards.values
                phase = .chooseBoard
            }
        } catch {
            phase = .error
            errorMessage = Self.describe(error)
        }
    }

    /// Continues a load the user paused on to choose between several boards.
    public func selectBoard(_ board: JiraBoard) async {
        phase = .loading
        errorMessage = nil
        availableBoards = []
        await loadBoard(board)
    }

    private func loadBoard(_ board: JiraBoard) async {
        do {
            let configuration = try await client.getBoardConfiguration(boardId: board.id)
            let sprint = try await client.getActiveSprint(boardId: board.id)

            let jql: String
            if let sprint {
                sprintName = sprint.name
                // Done cards are included on purpose — a board without its Done
                // column is a lie about where the work is.
                //
                // My open backlog rides along: an issue created from a local task
                // ("Convert to Jira") is filed straight into the project with no
                // sprint, so a sprint-only query would show it in the task list
                // but nowhere on the board. Done backlog cards stay out — they're
                // history, not work in this sprint.
                jql = "project = \"\(projectKey)\" AND assignee = currentUser()"
                    + " AND (sprint = \(sprint.id) OR (sprint is EMPTY AND statusCategory != Done))"
            } else {
                // Kanban boards (and scrum boards between sprints) have no active
                // sprint; fall back to the whole project so the board isn't empty.
                sprintName = nil
                jql = "project = \"\(projectKey)\" AND assignee = currentUser()"
            }

            let issues = try await fetchAllIssues(jql: jql)
            columns = Self.buildColumns(configuration: configuration, issues: issues)
            phase = .loaded
        } catch {
            phase = .error
            errorMessage = Self.describe(error)
        }
    }

    /// `POST /search/jql` does not report a total — pages are walked by
    /// `nextPageToken` until it stops coming back.
    private func fetchAllIssues(jql: String) async throws -> [JiraIssue] {
        var all: [JiraIssue] = []
        var token: String?
        repeat {
            let page = try await client.searchJQL(
                jql: jql,
                maxResults: 100,
                nextPageToken: token,
                fields: ["summary", "status", "priority", "issuetype", "timeoriginalestimate"]
            )
            all.append(contentsOf: page.issues)
            token = page.nextPageToken
        } while token != nil
        return all
    }

    /// Sorts issues into columns by status id. A card whose status maps to no
    /// column collects in a trailing "Other" column rather than disappearing.
    static func buildColumns(configuration: JiraBoardConfiguration, issues: [JiraIssue]) -> [Column] {
        var columns = configuration.columnConfig.columns.map { column in
            Column(id: column.name,
                   name: column.name,
                   statusIds: Set(column.statuses.map(\.id)),
                   cards: [],
                   isOther: false)
        }
        var orphans: [Card] = []

        for issue in issues {
            let card = Card(issue)
            if let statusId = card.statusId,
               let index = columns.firstIndex(where: { $0.statusIds.contains(statusId) }) {
                columns[index].cards.append(card)
            } else {
                orphans.append(card)
            }
        }

        if !orphans.isEmpty {
            columns.append(Column(id: Column.otherID,
                                  name: "Other",
                                  statusIds: [],
                                  cards: orphans,
                                  isOther: true))
        }
        return columns
    }

    // MARK: - Move (drag = transition)

    /// Moves a card to another column by performing the matching Jira transition.
    ///
    /// Optimistic: the card jumps to the target column immediately. Then we ask
    /// for the issue's transitions and pick the one whose target status is in the
    /// column. If none matches, or the one that does needs a Jira field screen we
    /// can't render, or the transition POST fails — the card snaps back and an
    /// explanatory message is published.
    public func move(issueKey: String, toColumnID columnID: String) async {
        guard let sourceIndex = columns.firstIndex(where: { $0.cards.contains { $0.key == issueKey } }),
              let targetIndex = columns.firstIndex(where: { $0.id == columnID }),
              sourceIndex != targetIndex,
              let cardIndex = columns[sourceIndex].cards.firstIndex(where: { $0.key == issueKey }) else {
            return
        }

        let target = columns[targetIndex]
        // A drop onto "Other" has no status to transition into — there's nothing
        // to ask Jira for.
        if target.isOther {
            errorMessage = "\(issueKey) can't be moved into Other."
            return
        }

        let snapshot = columns
        let card = columns[sourceIndex].cards[cardIndex]

        // Optimistic: reflect the move before the network round-trip.
        columns[sourceIndex].cards.remove(at: cardIndex)
        columns[targetIndex].cards.append(card)
        errorMessage = nil

        do {
            let transitions = try await client.getTransitions(issueKey: issueKey)
            guard let transition = transitions.first(where: { transition in
                guard let toID = transition.toStatus?.id else { return false }
                return target.statusIds.contains(toID)
            }) else {
                columns = snapshot
                errorMessage = "\(issueKey) has no transition into \(target.name)."
                return
            }

            // A transition with a screen needs fields we can't render here.
            if transition.hasScreen {
                columns = snapshot
                errorMessage = "\(issueKey) needs a field screen — open it in Jira to move it to \(target.name)."
                return
            }

            try await client.doTransition(issueKey: issueKey, transitionId: transition.id)

            // Keep the card's status honest so a further drag maps correctly.
            if let landed = columns.firstIndex(where: { $0.id == columnID }),
               let moved = columns[landed].cards.firstIndex(where: { $0.key == issueKey }) {
                columns[landed].cards[moved].statusId = transition.toStatus?.id
                columns[landed].cards[moved].statusCategoryKey = transition.to.statusCategory.key
            }
        } catch {
            columns = snapshot
            errorMessage = "Couldn't move \(issueKey): \(Self.describe(error))"
        }
    }

    // MARK: - Derived, for the header

    public var doneCount: Int {
        columns.reduce(0) { $0 + $1.cards.filter(\.isDone).count }
    }

    public var remainingCount: Int {
        columns.reduce(0) { $0 + $1.cards.filter { !$0.isDone }.count }
    }

    // MARK: - Helpers

    private static func describe(_ error: Error) -> String {
        if let jira = error as? JiraError { return jira.userMessage }
        return error.localizedDescription
    }
}

private extension JiraBoardModel.Card {
    init(_ issue: JiraIssue) {
        self.init(id: issue.key,
                  key: issue.key,
                  summary: issue.fields.summary ?? issue.key,
                  issueType: issue.fields.issuetype?.name,
                  priorityName: issue.fields.priority?.name,
                  estimateSeconds: issue.fields.timeoriginalestimate,
                  statusId: issue.fields.status?.id,
                  statusCategoryKey: issue.fields.status?.statusCategory.key)
    }
}
