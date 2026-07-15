import Foundation
import Testing
@testable import SharinganCore

@Suite("Jira integration", .serialized)
struct JiraIntegrationTests {

    @Test("ADF round-trips plain text paragraphs")
    func adfRoundTrip() {
        let text = "First line\n\nSecond line"
        let data = ADF.document(fromPlainText: text)
        #expect(ADF.plainText(from: data) == text)
    }

    @Test("ADF renders mentions and bullet lists")
    func adfRendersRichNodes() throws {
        let payload = """
        {
          "type": "doc",
          "version": 1,
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "mention", "attrs": { "text": "Bakhodir" } },
                { "type": "text", "text": " reviewed this" }
              ]
            },
            {
              "type": "bulletList",
              "content": [
                { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "One" }] }] },
                { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Two" }] }] }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        #expect(ADF.plainText(from: payload) == "@Bakhodir reviewed this\n- One\n- Two")
    }

    @Test("JiraService connect stores normalized site and token")
    @MainActor
    func jiraServiceConnects() async throws {
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let keychainService = "com.bakhod1r.sharingan.jira.tests.\(UUID().uuidString)"
        var tokenStore: [String: String] = [:]
        defer {
            defaults.removePersistentDomain(forName: suite)
            TestURLProtocol.reset()
        }

        let session = TestURLProtocol.session { request in
            let body = """
            {
              "accountId": "abc123",
              "displayName": "Dev User",
              "emailAddress": "dev@example.com",
              "active": true
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), body)
        }

        let service = JiraService(defaults: defaults,
                                  client: JiraClient(session: session),
                                  keychainService: keychainService,
                                  readToken: { service, account in
                                      tokenStore["\(service)|\(account)"]
                                  },
                                  writeToken: { value, service, account in
                                      tokenStore["\(service)|\(account)"] = value
                                  },
                                  deleteToken: { service, account in
                                      tokenStore.removeValue(forKey: "\(service)|\(account)")
                                  })

        let success = await service.connect(siteURLString: "example.atlassian.net/browse/SHR-1",
                                            email: "dev@example.com",
                                            apiToken: "secret-token")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.url?.absoluteString == "https://example.atlassian.net/rest/api/3/myself")
        let expectedAuth = "Basic " + Data("dev@example.com:secret-token".utf8).base64EncodedString()
        #expect(sent.header("Authorization") == expectedAuth)

        #expect(success)
        #expect(service.isConnected)
        #expect(defaults.string(forKey: JiraService.siteURLDefaultsKey) == "https://example.atlassian.net")
        #expect(defaults.string(forKey: JiraService.emailDefaultsKey) == "dev@example.com")
        #expect(tokenStore["\(keychainService)|example.atlassian.net"] == "secret-token")

        service.disconnect()
        #expect(defaults.string(forKey: JiraService.siteURLDefaultsKey) == nil)
        #expect(tokenStore["\(keychainService)|example.atlassian.net"] == nil)
    }

    @Test("JiraClient maps rate limits")
    func jiraClientMapsRateLimit() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let response = try TestURLProtocol.response(for: request,
                                                        status: 429,
                                                        headers: ["Retry-After": "60"])
            let body = #"{"errorMessages":["Slow down"]}"#.data(using: .utf8)!
            return (response, body)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        do {
            _ = try await client.myself()
            Issue.record("Expected rate limit error")
        } catch let error as JiraError {
            #expect(error == .rateLimited(retryAfter: 60))
        }
    }

    @Test("JiraClient searchJQL uses POST with nextPageToken pagination")
    func jiraClientSearchJQL() async throws {
        defer { TestURLProtocol.reset() }
        let firstPage = """
        {
          "issues": [
            {
              "id": "10001",
              "key": "SHR-1",
              "self": "https://example.atlassian.net/rest/api/3/issue/10001",
              "fields": {
                "summary": "Test issue",
                "status": { "name": "In Progress", "statusCategory": { "key": "indeterminate" } },
                "priority": { "name": "High" },
                "labels": ["bug", "urgent"],
                "duedate": "2025-12-31",
                "timeoriginalestimate": 7200,
                "description": { "type": "doc", "version": 1, "content": [] },
                "project": { "key": "SHR", "name": "Sharingan" },
                "issuetype": { "name": "Task" },
                "components": [{ "name": "Backend" }],
                "updated": "2025-01-15T10:00:00.000+0000"
              }
            }
          ],
          "nextPageToken": "abc123"
        }
        """.data(using: .utf8)!
        let secondPage = """
        {
          "issues": [
            {
              "id": "10002",
              "key": "SHR-2",
              "self": "https://example.atlassian.net/rest/api/3/issue/10002",
              "fields": {
                "summary": "Second page issue",
                "status": { "name": "To Do", "statusCategory": { "key": "new" } },
                "project": { "key": "SHR", "name": "Sharingan" },
                "issuetype": { "name": "Task" },
                "updated": "2025-01-15T10:00:00.000+0000"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let session = TestURLProtocol.session { request in
            let page = TestURLProtocol.requests.count <= 1 ? firstPage : secondPage
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), page)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let jql = "assignee = currentUser() AND statusCategory != Done"
        let result = try await client.searchJQL(jql: jql, maxResults: 50, nextPageToken: nil)
        let page2 = try await client.searchJQL(jql: jql, maxResults: 50, nextPageToken: result.nextPageToken)

        let requests = TestURLProtocol.requests
        #expect(requests.count == 2)

        let first = try #require(requests.first)
        #expect(first.method == "POST")
        #expect(first.url?.path == "/rest/api/3/search/jql")
        #expect(first.header("Content-Type") == "application/json")
        let firstBody = try first.jsonObject()
        #expect(firstBody["jql"] as? String == jql)
        #expect(firstBody["maxResults"] as? Int == 50)
        #expect(firstBody["nextPageToken"] == nil)

        let second = try #require(requests.last)
        #expect(second.method == "POST")
        #expect(second.url?.path == "/rest/api/3/search/jql")
        let secondBody = try second.jsonObject()
        #expect(secondBody["jql"] as? String == jql)
        #expect(secondBody["nextPageToken"] as? String == "abc123")

        #expect(result.issues.count == 1)
        #expect(result.issues[0].key == "SHR-1")
        #expect(result.issues[0].id == "10001")
        #expect(result.issues[0].fields.summary == "Test issue")
        #expect(result.issues[0].fields.status?.name == "In Progress")
        #expect(result.issues[0].fields.priority?.name == "High")
        #expect(result.issues[0].fields.labels == ["bug", "urgent"])
        #expect(result.issues[0].fields.duedate == "2025-12-31")
        #expect(result.issues[0].fields.timeoriginalestimate == 7200)
        #expect(result.nextPageToken == "abc123")

        #expect(page2.issues.map(\.key) == ["SHR-2"])
        #expect(page2.nextPageToken == nil)
    }

    @Test("JiraClient getIssue fetches full issue with editmeta")
    func jiraClientGetIssue() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "id": "10001",
              "key": "SHR-1",
              "self": "https://example.atlassian.net/rest/api/3/issue/10001",
              "fields": {
                "summary": "Test issue",
                "status": { "name": "In Progress", "statusCategory": { "key": "indeterminate" } },
                "priority": { "name": "High" },
                "labels": ["bug"],
                "duedate": "2025-12-31",
                "timeoriginalestimate": 7200,
                "description": { "type": "doc", "version": 1, "content": [] },
                "project": { "key": "SHR", "name": "Sharingan" },
                "issuetype": { "name": "Task" },
                "components": [{ "name": "Backend" }],
                "updated": "2025-01-15T10:00:00.000+0000"
              },
              "editmeta": {
                "fields": {
                  "summary": { "required": true, "schema": { "type": "string" } },
                  "description": { "required": false, "schema": { "type": "string" } },
                  "priority": { "required": false, "schema": { "type": "priority" } },
                  "labels": { "required": false, "schema": { "type": "array", "items": "string" } },
                  "duedate": { "required": false, "schema": { "type": "date" } },
                  "timeoriginalestimate": { "required": false, "schema": { "type": "timetracking" } }
                }
              }
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let issue = try await client.getIssue(key: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1")

        #expect(issue.id == "10001")
        #expect(issue.key == "SHR-1")
        #expect(issue.fields.summary == "Test issue")
        #expect(issue.fields.status?.name == "In Progress")
        #expect(issue.editMeta?.fields["summary"]?.required == true)
        #expect(issue.editMeta?.fields["priority"]?.schema.type == "priority")
    }

    @Test("JiraClient updateIssue sends PUT with fields")
    func jiraClientUpdateIssue() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            (try TestURLProtocol.response(for: request, status: 204), Data())
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let fields = JiraIssueUpdateFields(
            summary: "Updated summary",
            description: try JSONDecoder().decode(JiraADFDocument.self, from: ADF.document(fromPlainText: "New description")),
            priority: JiraPriorityInput(id: "3"),
            labels: ["bug", "frontend"],
            duedate: "2025-12-31",
            timeoriginalestimate: 3600
        )
        try await client.updateIssue(key: "SHR-1", fields: fields)

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "PUT")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1")

        let body = try sent.jsonObject()
        let fieldsDict = try #require(body["fields"] as? [String: Any])
        #expect(fieldsDict["summary"] as? String == "Updated summary")
        #expect((fieldsDict["description"] as? [String: Any])?["type"] as? String == "doc")
        #expect((fieldsDict["priority"] as? [String: Any])?["id"] as? String == "3")
        #expect(fieldsDict["labels"] as? [String] == ["bug", "frontend"])
        #expect(fieldsDict["duedate"] as? String == "2025-12-31")
        #expect(fieldsDict["timeoriginalestimate"] as? Int == 3600)
    }

    @Test("JiraClient getTransitions returns available transitions")
    func jiraClientGetTransitions() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "transitions": [
                { "id": "21", "name": "In Progress", "to": { "name": "In Progress", "statusCategory": { "key": "indeterminate" } } },
                { "id": "31", "name": "Code Review", "to": { "name": "Code Review", "statusCategory": { "key": "indeterminate" } } },
                { "id": "41", "name": "Done", "to": { "name": "Done", "statusCategory": { "key": "done" } } }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let transitions = try await client.getTransitions(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1/transitions")

        #expect(transitions.count == 3)
        #expect(transitions[0].id == "21")
        #expect(transitions[0].name == "In Progress")
        #expect(transitions[0].to.statusCategory.key == "indeterminate")
        #expect(transitions[2].to.statusCategory.key == "done")
    }

    @Test("JiraClient doTransition posts transition ID")
    func jiraClientDoTransition() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            (try TestURLProtocol.response(for: request, status: 204), Data())
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        try await client.doTransition(issueKey: "SHR-1", transitionId: "31")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1/transitions")

        let body = try sent.jsonObject()
        let transition = try #require(body["transition"] as? [String: Any])
        #expect(transition["id"] as? String == "31")
    }

    @Test("JiraClient addComment posts comment body as ADF")
    func jiraClientAddComment() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "id": "10001",
              "self": "https://example.atlassian.net/rest/api/3/issue/10001/comment/10001",
              "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Test comment" }] }] },
              "author": { "accountId": "abc", "displayName": "Dev User" },
              "created": "2025-01-15T10:00:00.000+0000",
              "updated": "2025-01-15T10:00:00.000+0000"
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 201), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let comment = try await client.addComment(issueKey: "SHR-1", body: "Test comment")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1/comment")

        let body = try sent.jsonObject()
        let bodyDict = try #require(body["body"] as? [String: Any])
        #expect(bodyDict["type"] as? String == "doc")
        #expect(comment.id == "10001")
        #expect(comment.plainTextBody == "Test comment")
    }

    @Test("JiraClient getComments returns paginated comments")
    func jiraClientGetComments() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "startAt": 0,
              "maxResults": 20,
              "total": 1,
              "comments": [
                {
                  "id": "10001",
                  "self": "https://example.atlassian.net/rest/api/3/issue/10001/comment/10001",
                  "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Test comment" }] }] },
                  "author": { "accountId": "abc", "displayName": "Dev User" },
                  "created": "2025-01-15T10:00:00.000+0000",
                  "updated": "2025-01-15T10:00:00.000+0000"
                }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let result = try await client.getComments(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1/comment")

        #expect(result.comments.count == 1)
        #expect(result.comments[0].id == "10001")
        #expect(result.comments[0].plainTextBody == "Test comment")
        #expect(result.comments[0].author.displayName == "Dev User")
    }

    @Test("JiraClient getChangelog returns history")
    func jiraClientGetChangelog() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "startAt": 0,
              "maxResults": 100,
              "total": 1,
              "histories": [
                {
                  "id": "10001",
                  "author": { "accountId": "abc", "displayName": "Dev User" },
                  "created": "2025-01-15T10:00:00.000+0000",
                  "items": [
                    { "field": "status", "fieldtype": "jira", "from": "10001", "fromString": "To Do", "to": "3", "toString": "In Progress" }
                  ]
                }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let result = try await client.getChangelog(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1/changelog")

        #expect(result.histories.count == 1)
        #expect(result.histories[0].id == "10001")
        #expect(result.histories[0].items[0].field == "status")
        #expect(result.histories[0].items[0].fromString == "To Do")
        #expect(result.histories[0].items[0].toString == "In Progress")
    }

    @Test("JiraClient addWorklog posts worklog with adjustEstimate=auto")
    func jiraClientAddWorklog() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "id": "10001",
              "self": "https://example.atlassian.net/rest/api/3/issue/10001/worklog/10001",
              "author": { "accountId": "abc", "displayName": "Dev User" },
              "comment": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Focus session from Sharingan 🍅" }] }] },
              "started": "2025-01-15T10:00:00.000+0000",
              "timeSpent": "1500",
              "timeSpentSeconds": 1500,
              "updated": "2025-01-15T10:00:00.000+0000"
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 201), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let worklog = try await client.addWorklog(
            issueKey: "SHR-1",
            timeSpentSeconds: 1500,
            started: "2025-01-15T10:00:00.000+0000",
            comment: "Focus session from Sharingan 🍅"
        )

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1/worklog")
        #expect(sent.url?.query?.contains("adjustEstimate=auto") == true)

        let body = try sent.jsonObject()
        #expect(body["timeSpentSeconds"] as? Int == 1500)
        #expect(body["started"] as? String == "2025-01-15T10:00:00.000+0000")
        let comment = try #require(body["comment"] as? [String: Any])
        #expect(comment["type"] as? String == "doc")
        #expect(worklog.id == "10001")
        #expect(worklog.timeSpentSeconds == 1500)
    }

    @Test("JiraClient getWorklogs returns worklogs")
    func jiraClientGetWorklogs() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "startAt": 0,
              "maxResults": 20,
              "total": 1,
              "worklogs": [
                {
                  "id": "10001",
                  "self": "https://example.atlassian.net/rest/api/3/issue/10001/worklog/10001",
                  "author": { "accountId": "abc", "displayName": "Dev User" },
                  "comment": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Focus session" }] }] },
                  "started": "2025-01-15T10:00:00.000+0000",
                  "timeSpent": "1500",
                  "timeSpentSeconds": 1500,
                  "updated": "2025-01-15T10:00:00.000+0000"
                }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let result = try await client.getWorklogs(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1/worklog")

        #expect(result.worklogs.count == 1)
        #expect(result.worklogs[0].id == "10001")
        #expect(result.worklogs[0].timeSpentSeconds == 1500)
    }

    @Test("JiraClient getProjects returns projects")
    func jiraClientGetProjects() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "startAt": 0,
              "maxResults": 50,
              "total": 2,
              "isLast": true,
              "values": [
                { "id": "10000", "key": "SHR", "name": "Sharingan", "projectTypeKey": "software" },
                { "id": "10001", "key": "DEV", "name": "Development", "projectTypeKey": "software" }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let projects = try await client.getProjects()

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/api/3/project/search")

        #expect(projects.values.count == 2)
        #expect(projects.values[0].key == "SHR")
        #expect(projects.values[0].name == "Sharingan")
        #expect(projects.values[1].key == "DEV")
    }

    @Test("JiraClient getIssueTypes returns issue types for project")
    func jiraClientGetIssueTypes() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            [
              { "id": "10001", "name": "Task", "description": "A task", "iconUrl": "https://...", "subtask": false },
              { "id": "10002", "name": "Bug", "description": "A bug", "iconUrl": "https://...", "subtask": false },
              { "id": "10003", "name": "Sub-task", "description": "A subtask", "iconUrl": "https://...", "subtask": true }
            ]
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let types = try await client.getIssueTypes(projectId: "10000")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/api/3/issuetype/project")
        #expect(sent.url?.query?.contains("projectId=10000") == true)

        #expect(types.values.count == 3)
        #expect(types.values[0].name == "Task")
        #expect(types.values[0].subtask == false)
        #expect(types.values[2].name == "Sub-task")
        #expect(types.values[2].subtask == true)
    }

    @Test("JiraClient getEditMeta returns edit metadata for issue")
    func jiraClientGetEditMeta() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "fields": {
                "summary": { "required": true, "schema": { "type": "string" } },
                "description": { "required": false, "schema": { "type": "string" } },
                "priority": { "required": false, "schema": { "type": "priority", "allowedValues": [{ "id": "1", "name": "Highest" }, { "id": "2", "name": "High" }, { "id": "3", "name": "Medium" }] } },
                "labels": { "required": false, "schema": { "type": "array", "items": "string" } },
                "duedate": { "required": false, "schema": { "type": "date" } }
              }
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let editMeta = try await client.getEditMeta(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/api/3/issue/SHR-1/editmeta")

        #expect(editMeta.fields["summary"]?.required == true)
        #expect(editMeta.fields["priority"]?.schema.type == "priority")
        #expect(editMeta.fields["priority"]?.schema.allowedValues?.count == 3)
        #expect(editMeta.fields["labels"]?.schema.items == "string")
    }

    @Test("JiraClient Agile API - getBoards returns boards")
    func jiraClientGetBoards() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "maxResults": 50,
              "startAt": 0,
              "total": 1,
              "isLast": true,
              "values": [
                { "id": 1, "name": "Sharingan Board", "type": "scrum", "location": { "projectId": 10000, "displayName": "Sharingan" } }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let result = try await client.getBoards()

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/agile/1.0/board")

        #expect(result.values.count == 1)
        #expect(result.values[0].id == 1)
        #expect(result.values[0].name == "Sharingan Board")
        #expect(result.values[0].type == "scrum")
    }

    @Test("JiraClient Agile API - getBoardConfiguration returns columns")
    func jiraClientGetBoardConfiguration() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "columnConfig": {
                "columns": [
                  { "name": "Backlog", "statuses": [{ "id": "1", "self": "https://..." }] },
                  { "name": "In Progress", "statuses": [{ "id": "3", "self": "https://..." }] },
                  { "name": "Done", "statuses": [{ "id": "5", "self": "https://..." }] }
                ]
              }
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let config = try await client.getBoardConfiguration(boardId: 1)

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/agile/1.0/board/1/configuration")

        #expect(config.columnConfig.columns.count == 3)
        #expect(config.columnConfig.columns[0].name == "Backlog")
        #expect(config.columnConfig.columns[1].name == "In Progress")
        #expect(config.columnConfig.columns[2].name == "Done")
    }

    @Test("JiraClient Agile API - getActiveSprint returns active sprint")
    func jiraClientGetActiveSprint() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "maxResults": 50,
              "startAt": 0,
              "total": 1,
              "isLast": true,
              "values": [
                { "id": 1, "name": "Sprint 1", "state": "active", "startDate": "2025-01-01T00:00:00.000Z", "endDate": "2025-01-14T23:59:59.000Z", "completeDate": null }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let sprint = try await client.getActiveSprint(boardId: 1)

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/agile/1.0/board/1/sprint")
        #expect(sent.url?.query?.contains("state=active") == true)

        #expect(sprint?.id == 1)
        #expect(sprint?.name == "Sprint 1")
        #expect(sprint?.state == "active")
    }

    @Test("JiraClient Agile API - getSprintIssues returns sprint issues")
    func jiraClientGetSprintIssues() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "maxResults": 50,
              "startAt": 0,
              "total": 1,
              "isLast": true,
              "issues": [
                { "id": "10001", "key": "SHR-1", "fields": { "summary": "Test", "status": { "name": "In Progress" } } }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(session: session)
        await client.configure(siteURL: try JiraService.normalizeSiteURL("example.atlassian.net"),
                               email: "dev@example.com",
                               apiToken: "secret-token")

        let result = try await client.getSprintIssues(sprintId: 1)

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/rest/agile/1.0/sprint/1/issue")

        #expect(result.issues.count == 1)
        #expect(result.issues[0].key == "SHR-1")
    }
}

extension URLRequest {
    /// The request body as seen from inside a `URLProtocol`.
    ///
    /// URLSession moves `httpBody` into `httpBodyStream` by the time a request
    /// reaches a custom protocol, so `httpBody` always reads back nil there —
    /// assertions must drain the stream instead.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// One request as it reached the stub, recorded so the test body — not the
/// `URLProtocol` callback — can assert on it.
///
/// `startLoading()` runs on URLSession's queue, outside the test's task-local
/// context, so any `#expect` there is orphaned onto `Test «unknown»` and cannot
/// fail the test. Handlers must only build responses; assertions belong after
/// the `await`, against these records.
private struct RecordedRequest: @unchecked Sendable {
    let request: URLRequest
    /// Drained at record time — the body stream is single-pass.
    let body: Data?

    var method: String? { request.httpMethod }
    var url: URL? { request.url }

    /// Case-insensitive, matching HTTP header semantics.
    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }

    func jsonObject() throws -> [String: Any] {
        let data = try #require(body, "request had no body")
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any],
                            "request body was not a JSON object")
    }
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requests: [RecordedRequest] = []

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    /// Every request the stub saw this test, in order. The suite is
    /// `.serialized`, and `reset()` clears this between tests.
    static var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _requests = []
    }

    private static func record(_ recorded: RecordedRequest) {
        lock.lock(); defer { lock.unlock() }
        _requests.append(recorded)
    }

    // MARK: - Response builders (no assertions — handlers run off-test)

    static func response(for request: URLRequest,
                         status: Int,
                         headers: [String: String] = [:]) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard let response = HTTPURLResponse(url: url,
                                             statusCode: status,
                                             httpVersion: nil,
                                             headerFields: headers) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    static func jsonResponse(for request: URLRequest, status: Int) throws -> HTTPURLResponse {
        try response(for: request, status: status, headers: ["Content-Type": "application/json"])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Self.record(RecordedRequest(request: request, body: request.bodyData))

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        reset()
        Self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }
}
