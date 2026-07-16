import Foundation

/// Minimal Jira REST models needed for connection/auth and early issue fetches.
public struct JiraMyself: Codable, Equatable, Sendable {
    public let accountId: String
    public let displayName: String
    public let emailAddress: String?
    public let active: Bool?

    public init(accountId: String, displayName: String,
                emailAddress: String? = nil, active: Bool? = nil) {
        self.accountId = accountId
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.active = active
    }
}

/// Jira's error payload is annoyingly loose: some responses only populate
/// `errorMessages`, others put field-specific strings under `errors`.
struct JiraErrorEnvelope: Decodable, Equatable, Sendable {
    let errorMessages: [String]?
    let errors: [String: String]?

    var flattenedMessages: [String] {
        let fieldErrors = (errors ?? [:])
            .sorted { $0.key < $1.key }
            .map { key, value in "\(key): \(value)" }
        return (errorMessages ?? []) + fieldErrors
    }
}

public struct JiraUserIdentity: Equatable, Sendable {
    public let accountId: String
    public let displayName: String
    public let emailAddress: String?

    public init(accountId: String, displayName: String, emailAddress: String?) {
        self.accountId = accountId
        self.displayName = displayName
        self.emailAddress = emailAddress
    }

    init(myself: JiraMyself) {
        self.init(accountId: myself.accountId,
                  displayName: myself.displayName,
                  emailAddress: myself.emailAddress)
    }
}

// MARK: - Search / Issues

public struct JiraSearchResult: Decodable, Equatable, Sendable {
    public let issues: [JiraIssue]
    public let nextPageToken: String?
    public let total: Int?

    public init(issues: [JiraIssue], nextPageToken: String?, total: Int?) {
        self.issues = issues
        self.nextPageToken = nextPageToken
        self.total = total
    }
}

public struct JiraIssue: Decodable, Equatable, Sendable {
    public let id: String
    public let key: String
    public let `self`: String
    public let fields: JiraIssueFields
    public let editMeta: JiraEditMeta?

    public init(id: String, key: String, selfLink: String, fields: JiraIssueFields, editMeta: JiraEditMeta?) {
        self.id = id
        self.key = key
        self.`self` = selfLink
        self.fields = fields
        self.editMeta = editMeta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        key = try container.decode(String.self, forKey: .key)
        // The Agile API omits `self` on the trimmed issues it returns for a sprint.
        self.`self` = try container.decodeIfPresent(String.self, forKey: .`self`) ?? ""
        fields = try container.decode(JiraIssueFields.self, forKey: .fields)
        editMeta = try container.decodeIfPresent(JiraEditMeta.self, forKey: .editMeta)
    }

    // Jira spells the expanded edit metadata `editmeta`, all lowercase.
    private enum CodingKeys: String, CodingKey {
        case id, key, fields
        case `self`
        case editMeta = "editmeta"
    }
}

public struct JiraIssueFields: Decodable, Equatable, Sendable {
    public let summary: String?
    public let status: JiraStatus?
    public let priority: JiraPriority?
    public let labels: [String]?
    public let duedate: String?
    public let timeoriginalestimate: Int?
    public let description: JiraADFDocument?
    public let project: JiraProject?
    public let issuetype: JiraIssueType?
    public let components: [JiraComponent]?
    public let updated: String?
    public let assignee: JiraUser?
    public let reporter: JiraUser?
    public let created: String?
    public let resolution: JiraResolution?
    public let fixVersions: [JiraVersion]?
    public let customfield_10020: JiraSprint?
    /// The parent issue, present on sub-tasks (and on Story→Epic links in
    /// team-managed projects). Drives nesting on import.
    public let parent: JiraParentRef?

    public init(summary: String?, status: JiraStatus?, priority: JiraPriority?, labels: [String]?, duedate: String?, timeoriginalestimate: Int?, description: JiraADFDocument?, project: JiraProject?, issuetype: JiraIssueType?, components: [JiraComponent]?, updated: String?, assignee: JiraUser?, reporter: JiraUser?, created: String?, resolution: JiraResolution?, fixVersions: [JiraVersion]?, customfield_10020: JiraSprint?, parent: JiraParentRef? = nil) {
        self.summary = summary
        self.status = status
        self.priority = priority
        self.labels = labels
        self.duedate = duedate
        self.timeoriginalestimate = timeoriginalestimate
        self.description = description
        self.project = project
        self.issuetype = issuetype
        self.components = components
        self.updated = updated
        self.assignee = assignee
        self.reporter = reporter
        self.created = created
        self.resolution = resolution
        self.fixVersions = fixVersions
        self.customfield_10020 = customfield_10020
        self.parent = parent
    }
}

/// Minimal reference to a sub-task's parent issue.
public struct JiraParentRef: Decodable, Equatable, Sendable {
    public let id: String
    public let key: String

    public init(id: String, key: String) {
        self.id = id
        self.key = key
    }

    private enum CodingKeys: String, CodingKey { case id, key }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
    }
}

public struct JiraStatus: Decodable, Equatable, Sendable {
    /// Status id — the only reliable key for board-column mapping, since a
    /// custom workflow renames statuses freely. Optional: some trimmed status
    /// objects omit it.
    public let id: String?
    public let name: String
    public let statusCategory: JiraStatusCategory

    public init(id: String? = nil, name: String, statusCategory: JiraStatusCategory) {
        self.id = id
        self.name = name
        self.statusCategory = statusCategory
    }

    // Jira omits `statusCategory` on the trimmed status objects returned by the
    // Agile API, so fall back to Jira's own "undefined" category rather than
    // failing the whole page of issues.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        statusCategory = try container.decodeIfPresent(JiraStatusCategory.self, forKey: .statusCategory)
            ?? JiraStatusCategory(key: "undefined", name: "", colorName: nil)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, statusCategory
    }
}

public struct JiraStatusCategory: Decodable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let colorName: String?

    public init(key: String, name: String, colorName: String?) {
        self.key = key
        self.name = name
        self.colorName = colorName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? "undefined"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName)
    }

    private enum CodingKeys: String, CodingKey {
        case key, name, colorName
    }
}

public struct JiraPriority: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let iconUrl: String?

    public init(id: String, name: String, iconUrl: String?) {
        self.id = id
        self.name = name
        self.iconUrl = iconUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, iconUrl
    }
}

public struct JiraProject: Decodable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let id: String

    public init(key: String, name: String, id: String) {
        self.key = key
        self.name = name
        self.id = id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case key, name, id
    }
}

public struct JiraIssueType: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let iconUrl: String?
    public let subtask: Bool

    public init(id: String, name: String, iconUrl: String?, subtask: Bool) {
        self.id = id
        self.name = name
        self.iconUrl = iconUrl
        self.subtask = subtask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl)
        subtask = try container.decodeIfPresent(Bool.self, forKey: .subtask) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, iconUrl, subtask
    }
}

public struct JiraComponent: Decodable, Equatable, Sendable {
    public let id: String?
    public let name: String
    public let description: String?

    public init(id: String?, name: String, description: String?) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct JiraUser: Decodable, Equatable, Sendable {
    public let accountId: String
    public let displayName: String
    public let emailAddress: String?
    public let active: Bool?

    public init(accountId: String, displayName: String, emailAddress: String?, active: Bool?) {
        self.accountId = accountId
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.active = active
    }
}

public struct JiraResolution: Decodable, Equatable, Sendable {
    public let name: String
    public let description: String?

    public init(name: String, description: String?) {
        self.name = name
        self.description = description
    }
}

public struct JiraVersion: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let released: Bool
    public let releaseDate: String?

    public init(id: String, name: String, released: Bool, releaseDate: String?) {
        self.id = id
        self.name = name
        self.released = released
        self.releaseDate = releaseDate
    }
}

public struct JiraSprint: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let state: String
    public let startDate: String?
    public let endDate: String?
    public let completeDate: String?
    public let originBoardId: Int?

    public init(id: Int, name: String, state: String, startDate: String?, endDate: String?, completeDate: String?, originBoardId: Int?) {
        self.id = id
        self.name = name
        self.state = state
        self.startDate = startDate
        self.endDate = endDate
        self.completeDate = completeDate
        self.originBoardId = originBoardId
    }
}

public struct JiraADFDocument: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let content: [JiraADFNode]?

    public init(type: String, version: Int, content: [JiraADFNode]?) {
        self.type = type
        self.version = version
        self.content = content
    }
}

public struct JiraADFNode: Codable, Equatable, Sendable {
    public let type: String
    public let content: [JiraADFNode]?
    public let text: String?
    public let attrs: [String: AnyCodable]?

    public init(type: String, content: [JiraADFNode]?, text: String?, attrs: [String: AnyCodable]?) {
        self.type = type
        self.content = content
        self.text = text
        self.attrs = attrs
    }
}

public struct AnyCodable: Codable, Equatable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.value = NSNull() }
        else if let v = try? container.decode(Bool.self) { self.value = v }
        else if let v = try? container.decode(Int.self) { self.value = v }
        else if let v = try? container.decode(Double.self) { self.value = v }
        else if let v = try? container.decode(String.self) { self.value = v }
        else if let v = try? container.decode([AnyCodable].self) { self.value = v.map(\.value) }
        else if let v = try? container.decode([String: AnyCodable].self) { self.value = v.mapValues(\.value) }
        else { self.value = NSNull() }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is NSNull { try container.encodeNil() }
        else if let v = value as? Bool { try container.encode(v) }
        else if let v = value as? Int { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
        else if let v = value as? String { try container.encode(v) }
        else if let v = value as? [Any] { try container.encode(v.map(AnyCodable.init)) }
        else if let v = value as? [String: Any] { try container.encode(v.mapValues(AnyCodable.init)) }
        else { try container.encodeNil() }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull): return true
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        case (let l as [Any], let r as [Any]):
            return (l as NSArray).isEqual(to: r)
        case (let l as [String: Any], let r as [String: Any]):
            return NSDictionary(dictionary: l).isEqual(to: r)
        default: return false
        }
    }
}

public struct JiraEditMeta: Decodable, Equatable, Sendable {
    public let fields: [String: JiraEditMetaField]

    public init(fields: [String: JiraEditMetaField]) {
        self.fields = fields
    }
}

public struct JiraEditMetaField: Decodable, Equatable, Sendable {
    public let required: Bool
    public let schema: JiraEditMetaSchema
    public let name: String?
    public let key: String?
    public let hasDefaultValue: Bool?
    public let operations: [String]?
    public let allowedValues: [AnyCodable]?

    public init(required: Bool, schema: JiraEditMetaSchema, name: String?, key: String?, hasDefaultValue: Bool?, operations: [String]?, allowedValues: [AnyCodable]?) {
        self.required = required
        self.schema = schema
        self.name = name
        self.key = key
        self.hasDefaultValue = hasDefaultValue
        self.operations = operations
        self.allowedValues = allowedValues
    }
}

public struct JiraEditMetaSchema: Decodable, Equatable, Sendable {
    public let type: String
    public let items: String?
    public let system: String?
    public let custom: String?
    public let customId: Int?
    public let allowedValues: [AnyCodable]?

    public init(type: String, items: String?, system: String?, custom: String?, customId: Int?, allowedValues: [AnyCodable]?) {
        self.type = type
        self.items = items
        self.system = system
        self.custom = custom
        self.customId = customId
        self.allowedValues = allowedValues
    }
}

// MARK: - Transitions

public struct JiraTransition: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let to: JiraStatus
    /// True when applying this transition opens a Jira field screen (e.g. a
    /// required resolution) that Sharingan can't render — the board refuses it
    /// and sends the user to Jira instead.
    public let hasScreen: Bool

    /// Alias for `to`, spelled the way the board code reads it.
    public var toStatus: JiraStatus? { to }

    public init(id: String, name: String, to: JiraStatus, hasScreen: Bool = false) {
        self.id = id
        self.name = name
        self.to = to
        self.hasScreen = hasScreen
    }

    private enum CodingKeys: String, CodingKey { case id, name, to, hasScreen }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        to = try c.decode(JiraStatus.self, forKey: .to)
        hasScreen = try c.decodeIfPresent(Bool.self, forKey: .hasScreen) ?? false
    }
}

public struct JiraTransitionsResponse: Decodable, Equatable, Sendable {
    public let transitions: [JiraTransition]

    public init(transitions: [JiraTransition]) {
        self.transitions = transitions
    }
}

public struct JiraTransitionInput: Encodable, Equatable, Sendable {
    public let transition: JiraTransitionId

    public init(transitionId: String) {
        self.transition = JiraTransitionId(id: transitionId)
    }
}

public struct JiraTransitionId: Encodable, Equatable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

// MARK: - Comments

public struct JiraComment: Decodable, Equatable, Sendable {
    public let id: String
    public let `self`: String
    public let body: JiraADFDocument
    public let author: JiraUser
    public let created: String
    public let updated: String

    public init(id: String, selfLink: String, body: JiraADFDocument, author: JiraUser, created: String, updated: String) {
        self.id = id
        self.`self` = selfLink
        self.body = body
        self.author = author
        self.created = created
        self.updated = updated
    }

    public var plainTextBody: String {
        ADF.plainText(from: (try? JSONEncoder().encode(body)) ?? Data())
    }
}

public struct JiraCommentsResponse: Decodable, Equatable, Sendable {
    public let startAt: Int
    public let maxResults: Int
    public let total: Int
    public let comments: [JiraComment]

    public init(startAt: Int, maxResults: Int, total: Int, comments: [JiraComment]) {
        self.startAt = startAt
        self.maxResults = maxResults
        self.total = total
        self.comments = comments
    }
}

public struct JiraCommentInput: Encodable, Equatable, Sendable {
    public let body: JiraADFDocument

    public init(body: JiraADFDocument) {
        self.body = body
    }
}

// MARK: - Changelog

public struct JiraChangelog: Decodable, Equatable, Sendable {
    public let startAt: Int
    public let maxResults: Int
    public let total: Int
    public let histories: [JiraChangelogHistory]

    public init(startAt: Int, maxResults: Int, total: Int, histories: [JiraChangelogHistory]) {
        self.startAt = startAt
        self.maxResults = maxResults
        self.total = total
        self.histories = histories
    }
}

public struct JiraChangelogHistory: Decodable, Equatable, Sendable {
    public let id: String
    public let author: JiraUser
    public let created: String
    public let items: [JiraChangelogItem]

    public init(id: String, author: JiraUser, created: String, items: [JiraChangelogItem]) {
        self.id = id
        self.author = author
        self.created = created
        self.items = items
    }
}

public struct JiraChangelogItem: Decodable, Equatable, Sendable {
    public let field: String
    public let fieldtype: String
    public let from: String?
    public let fromString: String?
    public let to: String?
    public let toString: String?

    public init(field: String, fieldtype: String, from: String?, fromString: String?, to: String?, toString: String?) {
        self.field = field
        self.fieldtype = fieldtype
        self.from = from
        self.fromString = fromString
        self.to = to
        self.toString = toString
    }
}

// MARK: - Worklog

public struct JiraWorklog: Decodable, Equatable, Sendable {
    public let id: String
    public let `self`: String
    public let author: JiraUser
    public let comment: JiraADFDocument?
    public let started: String
    public let timeSpent: String
    public let timeSpentSeconds: Int
    public let created: String
    public let updated: String

    public init(id: String, selfLink: String, author: JiraUser, comment: JiraADFDocument?, started: String, timeSpent: String, timeSpentSeconds: Int, created: String, updated: String) {
        self.id = id
        self.`self` = selfLink
        self.author = author
        self.comment = comment
        self.started = started
        self.timeSpent = timeSpent
        self.timeSpentSeconds = timeSpentSeconds
        self.created = created
        self.updated = updated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        self.`self` = try container.decodeIfPresent(String.self, forKey: .`self`) ?? ""
        author = try container.decode(JiraUser.self, forKey: .author)
        comment = try container.decodeIfPresent(JiraADFDocument.self, forKey: .comment)
        started = try container.decodeIfPresent(String.self, forKey: .started) ?? ""
        timeSpent = try container.decodeIfPresent(String.self, forKey: .timeSpent) ?? ""
        timeSpentSeconds = try container.decodeIfPresent(Int.self, forKey: .timeSpentSeconds) ?? 0
        // `created`/`updated` are audit fields; a worklog missing one is still usable.
        created = try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, author, comment, started, timeSpent, timeSpentSeconds, created, updated
        case `self`
    }
}

public struct JiraWorklogResponse: Decodable, Equatable, Sendable {
    public let startAt: Int
    public let maxResults: Int
    public let total: Int
    public let worklogs: [JiraWorklog]

    public init(startAt: Int, maxResults: Int, total: Int, worklogs: [JiraWorklog]) {
        self.startAt = startAt
        self.maxResults = maxResults
        self.total = total
        self.worklogs = worklogs
    }
}

/// Body of `POST /rest/api/3/issue/{key}/worklog`.
///
/// `adjustEstimate` is deliberately absent: Jira only reads it as a query
/// parameter on this endpoint, and silently ignores it in the body.
public struct JiraWorklogInput: Encodable, Equatable, Sendable {
    public let timeSpentSeconds: Int
    public let started: String
    public let comment: JiraADFDocument?

    public init(timeSpentSeconds: Int, started: String, comment: JiraADFDocument? = nil) {
        self.timeSpentSeconds = timeSpentSeconds
        self.started = started
        self.comment = comment
    }
}

public struct JiraWorklogCreated: Decodable, Equatable, Sendable {
    public let id: String
    public let `self`: String
    public let timeSpent: String
    public let timeSpentSeconds: Int

    public init(id: String, selfLink: String, timeSpent: String, timeSpentSeconds: Int) {
        self.id = id
        self.`self` = selfLink
        self.timeSpent = timeSpent
        self.timeSpentSeconds = timeSpentSeconds
    }
}

// MARK: - Issue Update

public struct JiraIssueUpdateFields: Encodable, Equatable, Sendable {
    public let summary: String?
    public let description: JiraADFDocument?
    public let priority: JiraPriorityInput?
    public let labels: [String]?
    public let duedate: String?
    public let timeoriginalestimate: Int?

    public init(summary: String? = nil,
                description: JiraADFDocument? = nil,
                priority: JiraPriorityInput? = nil,
                labels: [String]? = nil,
                duedate: String? = nil,
                timeoriginalestimate: Int? = nil) {
        self.summary = summary
        self.description = description
        self.priority = priority
        self.labels = labels
        self.duedate = duedate
        self.timeoriginalestimate = timeoriginalestimate
    }
}

public struct JiraPriorityInput: Encodable, Equatable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

/// The fields for creating an issue — encodes to Jira's nested shape
/// (`project.key`, `issuetype.name`, `priority.name`). Priority goes by name;
/// Jira accepts either name or id.
public struct JiraIssueCreateFields: Encodable, Equatable, Sendable {
    public let projectKey: String
    public let issueTypeName: String
    public let summary: String
    public let priorityName: String?
    public let descriptionText: String?

    public init(projectKey: String, issueTypeName: String, summary: String,
                priorityName: String? = nil, descriptionText: String? = nil) {
        self.projectKey = projectKey
        self.issueTypeName = issueTypeName
        self.summary = summary
        self.priorityName = priorityName
        self.descriptionText = descriptionText
    }

    private struct KeyRef: Encodable { let key: String }
    private struct NameRef: Encodable { let name: String }
    private enum CodingKeys: String, CodingKey {
        case project, issuetype, summary, priority, description
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(KeyRef(key: projectKey), forKey: .project)
        try c.encode(NameRef(name: issueTypeName), forKey: .issuetype)
        try c.encode(summary, forKey: .summary)
        if let priorityName { try c.encode(NameRef(name: priorityName), forKey: .priority) }
        if let descriptionText {
            let adf = try JSONDecoder().decode(JiraADFDocument.self,
                                               from: ADF.document(fromPlainText: descriptionText))
            try c.encode(adf, forKey: .description)
        }
    }
}

/// The id + key Jira returns from a create.
public struct JiraIssueRef: Decodable, Equatable, Sendable {
    public let id: String
    public let key: String

    public init(id: String, key: String) {
        self.id = id
        self.key = key
    }
}

// MARK: - Projects / Issue Types / Boards / Sprints (Agile API)

public struct JiraProjectListResponse: Decodable, Equatable, Sendable {
    public let values: [JiraProject]
    public let startAt: Int
    public let maxResults: Int
    public let total: Int
    public let isLast: Bool

    public init(values: [JiraProject], startAt: Int, maxResults: Int, total: Int, isLast: Bool) {
        self.values = values
        self.startAt = startAt
        self.maxResults = maxResults
        self.total = total
        self.isLast = isLast
    }

    public var count: Int { values.count }
    public subscript(index: Int) -> JiraProject { values[index] }
}

/// Wrapper around `GET /rest/api/3/issuetype/project`.
///
/// That endpoint is unpaginated — it answers with a bare JSON array — so the
/// pagination fields are synthesized here to match the other list responses.
public struct JiraIssueTypeListResponse: Decodable, Equatable, Sendable {
    public let values: [JiraIssueType]
    public let startAt: Int
    public let maxResults: Int
    public let total: Int
    public let isLast: Bool

    public init(values: [JiraIssueType], startAt: Int, maxResults: Int, total: Int, isLast: Bool) {
        self.values = values
        self.startAt = startAt
        self.maxResults = maxResults
        self.total = total
        self.isLast = isLast
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let types = try container.decode([JiraIssueType].self)
        self.init(values: types,
                  startAt: 0,
                  maxResults: types.count,
                  total: types.count,
                  isLast: true)
    }

    public var count: Int { values.count }
    public subscript(index: Int) -> JiraIssueType { values[index] }
}

public struct JiraBoard: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let type: String
    public let location: JiraBoardLocation?

    public init(id: Int, name: String, type: String, location: JiraBoardLocation?) {
        self.id = id
        self.name = name
        self.type = type
        self.location = location
    }
}

/// A board's `location`. Only `projectId` is dependable: boards scoped to a user
/// rather than a project come back with just an id and a `displayName`.
public struct JiraBoardLocation: Decodable, Equatable, Sendable {
    public let projectKey: String?
    public let projectName: String?
    public let projectId: Int
    public let displayName: String?

    public init(projectKey: String?, projectName: String?, projectId: Int, displayName: String? = nil) {
        self.projectKey = projectKey
        self.projectName = projectName
        self.projectId = projectId
        self.displayName = displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectKey = try container.decodeIfPresent(String.self, forKey: .projectKey)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        projectId = try container.decodeIfPresent(Int.self, forKey: .projectId) ?? 0
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }

    private enum CodingKeys: String, CodingKey {
        case projectKey, projectName, projectId, displayName
    }
}

public struct JiraBoardListResponse: Decodable, Equatable, Sendable {
    public let values: [JiraBoard]
    public let startAt: Int
    public let maxResults: Int
    public let total: Int
    public let isLast: Bool

    public init(values: [JiraBoard], startAt: Int, maxResults: Int, total: Int, isLast: Bool) {
        self.values = values
        self.startAt = startAt
        self.maxResults = maxResults
        self.total = total
        self.isLast = isLast
    }
}

public struct JiraBoardConfiguration: Decodable, Equatable, Sendable {
    public let columnConfig: JiraColumnConfig
    public let statusMapping: [JiraStatusMapping]?

    public init(columnConfig: JiraColumnConfig, statusMapping: [JiraStatusMapping]?) {
        self.columnConfig = columnConfig
        self.statusMapping = statusMapping
    }
}

public struct JiraColumnConfig: Decodable, Equatable, Sendable {
    public let columns: [JiraBoardColumn]

    public init(columns: [JiraBoardColumn]) {
        self.columns = columns
    }
}

public struct JiraBoardColumn: Decodable, Equatable, Sendable {
    public let name: String
    public let statuses: [JiraStatusRef]

    public init(name: String, statuses: [JiraStatusRef]) {
        self.name = name
        self.statuses = statuses
    }
}

/// A status as referenced by a board column: the board configuration endpoint
/// returns only `self` and `id` here, never the status name.
public struct JiraStatusRef: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String?

    public init(id: String, name: String?) {
        self.id = id
        self.name = name
    }
}

public struct JiraStatusMapping: Decodable, Equatable, Sendable {
    public let statusId: String
    public let columnName: String

    public init(statusId: String, columnName: String) {
        self.statusId = statusId
        self.columnName = columnName
    }
}

public struct JiraSprintListResponse: Decodable, Equatable, Sendable {
    public let values: [JiraSprint]
    public let startAt: Int
    public let maxResults: Int
    public let total: Int
    public let isLast: Bool

    public init(values: [JiraSprint], startAt: Int, maxResults: Int, total: Int, isLast: Bool) {
        self.values = values
        self.startAt = startAt
        self.maxResults = maxResults
        self.total = total
        self.isLast = isLast
    }
}

/// `GET /rest/agile/1.0/sprint/{id}/issue`. Unlike the board and sprint lists,
/// this one paginates with startAt/total only — there is no `isLast` flag.
public struct JiraSprintIssuesResponse: Decodable, Equatable, Sendable {
    public let issues: [JiraIssue]
    public let startAt: Int
    public let maxResults: Int
    public let total: Int

    public init(issues: [JiraIssue], startAt: Int, maxResults: Int, total: Int) {
        self.issues = issues
        self.startAt = startAt
        self.maxResults = maxResults
        self.total = total
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        issues = try container.decodeIfPresent([JiraIssue].self, forKey: .issues) ?? []
        startAt = try container.decodeIfPresent(Int.self, forKey: .startAt) ?? 0
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? issues.count
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? issues.count
    }

    private enum CodingKeys: String, CodingKey {
        case issues, startAt, maxResults, total
    }
}

// MARK: - Search JQL Request

public struct JiraSearchJQLRequest: Encodable, Equatable, Sendable {
    public let jql: String
    public let maxResults: Int
    public let nextPageToken: String?
    public let fields: [String]?
    public let expand: [String]?

    public init(jql: String, maxResults: Int = 50, nextPageToken: String? = nil, fields: [String]? = nil, expand: [String]? = nil) {
        self.jql = jql
        self.maxResults = maxResults
        self.nextPageToken = nextPageToken
        self.fields = fields
        self.expand = expand
    }
}