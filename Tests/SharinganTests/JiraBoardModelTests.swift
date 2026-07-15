import Foundation
import Testing
@testable import SharinganCore

// Model gaps the Jira board needs: a card must be matched to a board column by
// its status *id* (names can't be trusted with a custom workflow), and a
// transition that opens a Jira field screen must be detectable so the board can
// refuse it and send the user to Jira instead.
@Suite("Jira board model fields")
struct JiraBoardModelFieldsTests {

    @Test("an issue's status decodes its id for column mapping")
    func statusDecodesID() throws {
        let json = Data("""
        { "id": "10", "key": "SHRGN-4",
          "fields": { "summary": "Task 1",
                      "status": { "id": "10001", "name": "In Progress",
                                  "statusCategory": { "key": "indeterminate" } } } }
        """.utf8)
        let issue = try JSONDecoder().decode(JiraIssue.self, from: json)
        #expect(issue.fields.status?.id == "10001")
    }

    @Test("status id is nil, not a failure, when Jira omits it")
    func statusIDOptional() throws {
        let json = Data("""
        { "name": "Done", "statusCategory": { "key": "done" } }
        """.utf8)
        let status = try JSONDecoder().decode(JiraStatus.self, from: json)
        #expect(status.id == nil)
        #expect(status.statusCategory.key == "done")
    }

    @Test("a transition exposes hasScreen and its target status id")
    func transitionExposesScreenAndTargetID() throws {
        let json = Data("""
        { "transitions": [
            { "id": "31", "name": "Code review", "hasScreen": true,
              "to": { "id": "10002", "name": "Code review",
                      "statusCategory": { "key": "indeterminate" } } },
            { "id": "41", "name": "Done", "hasScreen": false,
              "to": { "id": "10003", "name": "Done",
                      "statusCategory": { "key": "done" } } }
          ] }
        """.utf8)
        let response = try JSONDecoder().decode(JiraTransitionsResponse.self, from: json)
        let review = response.transitions[0]
        #expect(review.hasScreen)
        #expect(review.toStatus?.id == "10002")
        #expect(!response.transitions[1].hasScreen)
    }

    @Test("hasScreen defaults to false when Jira omits it")
    func hasScreenDefaultsFalse() throws {
        let json = Data("""
        { "id": "1", "name": "Start",
          "to": { "name": "In Progress", "statusCategory": { "key": "indeterminate" } } }
        """.utf8)
        let t = try JSONDecoder().decode(JiraTransition.self, from: json)
        #expect(!t.hasScreen)
    }
}
