import Foundation
import Testing
@testable import ClaudeUsage

/// Respuesta real de /api/oauth/usage (valores cambiados): fechas con microsegundos,
/// ventanas a null y campos que la app no usa.
let usageFixture = Data("""
{
  "five_hour": {"utilization": 25.0, "resets_at": "2026-10-13T12:59:00.456921+00:00"},
  "seven_day": {"utilization": 82.0, "resets_at": "2026-10-13T21:59:00.123456+00:00"},
  "seven_day_oauth_apps": null,
  "seven_day_opus": {"utilization": null, "resets_at": null},
  "seven_day_sonnet": null,
  "seven_day_breakdown": {"rows": [
    {"key": "claude_code", "display_name": "Claude Code", "percent": 90},
    {"key": "chats", "display_name": "Chats", "percent": 2}
  ]},
  "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null,
                  "utilization": null, "currency": null},
  "some_future_field": {"anything": true}
}
""".utf8)

@Suite("UsageService")
struct UsageServiceTests {

    // MARK: Credentials

    @Test func parsesKeychainCredentials() throws {
        let json = Data("""
        {"claudeAiOauth": {"accessToken": "sk-ant-oat-test", "refreshToken": "r",
                           "expiresAt": 1791903540000, "subscriptionType": "pro"}}
        """.utf8)
        let creds = try UsageService.parseCredentials(from: json)
        #expect(creds.accessToken == "sk-ant-oat-test")
        #expect(creds.subscriptionType == "pro")
        #expect(creds.expiresAt == Date(timeIntervalSince1970: 1_791_903_540))
    }

    @Test("Missing or malformed credentials are rejected", arguments: [
        "", "not json", "{}", #"{"claudeAiOauth": {}}"#,
        #"{"claudeAiOauth": {"accessToken": ""}}"#, #"{"claudeAiOauth": {"accessToken": 42}}"#,
    ])
    func rejectsInvalidCredentials(json: String) {
        #expect(throws: UsageError.noCredentials) {
            try UsageService.parseCredentials(from: Data(json.utf8))
        }
    }

    // MARK: Request & response

    @Test func requestCarriesAuthAndBetaHeaders() {
        let request = UsageService.makeRequest(token: "abc")
        #expect(request.url == UsageService.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test("HTTP status codes map to errors", arguments: [
        (401, UsageError.tokenExpired), (403, .tokenExpired), (429, .rateLimited),
        (500, .http(500)), (0, .http(0)),
    ] as [(Int, UsageError)])
    func statusMapping(status: Int, expected: UsageError) {
        #expect(throws: expected) { try UsageService.validate(status: status) }
    }

    @Test func okStatusPasses() throws {
        try UsageService.validate(status: 200)
    }

    @Test func decodesRealisticResponse() throws {
        let usage = try UsageService.decodeUsage(usageFixture)
        #expect(usage.fiveHour?.utilization == 25)
        #expect(usage.fiveHour?.resetDate == parseISODate("2026-10-13T12:59:00Z"))
        #expect(usage.sevenDay?.utilization == 82)
        #expect(usage.sevenDayOpus?.utilization == nil)
        #expect(usage.sevenDaySonnet == nil)
        #expect(usage.sevenDayBreakdown?.rows.map(\.displayName) == ["Claude Code", "Chats"])
        #expect(usage.extraUsage?.isEnabled == false)
    }

    @Test func decodesEmptyObject() throws {
        let usage = try UsageService.decodeUsage(Data("{}".utf8))
        #expect(usage.fiveHour == nil)
    }

    @Test func rejectsWrongTypes() {
        #expect(throws: DecodingError.self) {
            try UsageService.decodeUsage(Data(#"{"five_hour": {"utilization": "mucho"}}"#.utf8))
        }
    }

    @Test func errorMessagesAreUserFacing() {
        #expect(UsageError.http(502).errorDescription == "Error del servidor (HTTP 502).")
        #expect(UsageError.noCredentials.errorDescription?.contains("claude") == true)
    }
}

// MARK: - fetch() de extremo a extremo con la red simulada

@Suite("UsageService.fetch", .serialized)
struct UsageServiceFetchTests {
    let creds = Credentials(accessToken: "tok", expiresAt: nil, subscriptionType: "max")

    @Test func returnsDecodedUsageAndCredentials() async throws {
        let session = StubURLProtocol.session { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
            return (200, usageFixture)
        }
        let (usage, returned) = try await UsageService.fetch(credentials: { creds }, session: session)
        #expect(usage.fiveHour?.utilization == 25)
        #expect(returned.subscriptionType == "max")
    }

    @Test func expiredTokenSurfacesAsTokenExpired() async {
        let session = StubURLProtocol.session { _ in (401, Data()) }
        await #expect(throws: UsageError.tokenExpired) {
            try await UsageService.fetch(credentials: { creds }, session: session)
        }
    }

    @Test func missingCredentialsSkipTheNetwork() async {
        var requested = false
        let session = StubURLProtocol.session { _ in requested = true; return (200, usageFixture) }
        await #expect(throws: UsageError.noCredentials) {
            try await UsageService.fetch(credentials: { throw UsageError.noCredentials }, session: session)
        }
        #expect(!requested)
    }
}

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    static func session(_ handler: @escaping (URLRequest) -> (Int, Data)) -> URLSession {
        self.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
