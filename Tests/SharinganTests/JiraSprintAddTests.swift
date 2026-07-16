import Foundation
import Testing
@testable import SharinganCore

/// Verifies the wire shape of `JiraClient.addIssuesToSprint` — the POST that
/// backs the "Add new issues to the active sprint" setting.
@Suite(.serialized)
struct JiraSprintAddTests {

    @Test("addIssuesToSprint POSTs the issue keys to the sprint issue endpoint")
    func postsIssuesToSprint() async throws {
        SprintStub.reset()
        SprintStub.setHandler { req in
            (try SprintStub.noContent(req), Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SprintStub.self]
        let session = URLSession(configuration: config)
        let client = JiraClient(tokens: SprintStubTokens(), session: session)

        try await client.addIssuesToSprint(sprintId: 42, issueKeys: ["SHRGN-5", "SHRGN-6"])

        let sent = try #require(SprintStub.requests.last)
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.request.url?.path.hasSuffix("/rest/agile/1.0/sprint/42/issue") == true)
        let body = try #require(sent.body)
        let parsed = try JSONSerialization.jsonObject(with: body)
        let json = try #require(parsed as? [String: Any])
        #expect(json["issues"] as? [String] == ["SHRGN-5", "SHRGN-6"])
    }
}

private struct SprintStubTokens: JiraTokenProviding {
    func accessToken() async throws -> String { "at" }
    func cloudID() async throws -> String { "cloud-1" }
}

private struct RecordedRequest: @unchecked Sendable {
    let request: URLRequest
    let body: Data?
}

private final class SprintStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requests: [RecordedRequest] = []

    static var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }; return _requests
    }
    static func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock(); defer { lock.unlock() }; _handler = handler
    }
    static func reset() {
        lock.lock(); defer { lock.unlock() }; _handler = nil; _requests = []
    }
    static func noContent(_ request: URLRequest) throws -> HTTPURLResponse {
        guard let url = request.url,
              let r = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return r
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock(); let handler = Self._handler; Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); let size = 4096; var buf = [UInt8](repeating: 0, count: size)
            while stream.hasBytesAvailable {
                let read = stream.read(&buf, maxLength: size)
                if read <= 0 { break }
                data.append(buf, count: read)
            }
            body = data
        }
        Self.lock.lock(); Self._requests.append(RecordedRequest(request: request, body: body)); Self.lock.unlock()
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
}
