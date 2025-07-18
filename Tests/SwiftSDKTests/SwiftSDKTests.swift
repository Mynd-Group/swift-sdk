//
//  SwiftSDKTests.swift
//  AuthTests
//
//  Comprehensive test-suite for AuthClient.
//
//  • Uses Swift Testing 1.2+  →  https://github.com/apple/swift-testing
//  • Requires Swift 6 (or newer) tool-chain
//

import Foundation
import Testing

@testable import SwiftSDK

// MARK: – Test doubles

// -----------------------------------------------------------------------------
// 1. StubAuthProvider
//    • Simulates the authFunction injected via AuthClientConfig.
//    • Can return a sequence of results so we can model fallback scenarios.
// 2. StubHttpClient
//    • Conforms to the updated non-isolated HttpClientProtocol.
//    • Keeps an async call counter that is data-race-free.
// -----------------------------------------------------------------------------

actor StubAuthProvider {
    // Public inspection
    private(set) var calls = 0

    // Internal sequence of canned responses
    private var responses: [Result<AuthPayload, Error>]

    init(responses: [Result<AuthPayload, Error>]) {
        precondition(!responses.isEmpty, "Provide at least one response")
        self.responses = responses
    }

    /// Convenience initialiser for a single fixed result
    init(result: Result<AuthPayload, Error>) {
        self.init(responses: [result])
    }

    /// Callable from AuthClient
    func auth() async throws -> AuthPayloadProtocol {
        calls += 1
        let idx = min(calls - 1, responses.count - 1) // clamp to last element
        return try responses[idx].get()
    }
}

/// Thread-safe counter used by the StubHttpClient
private actor CallTracker {
    private var value = 0
    func bump() { value += 1 }
    var current: Int { value }
}

/// Test-double that fulfils the *nonisolated* requirements of HttpClientProtocol.
final class StubHttpClient: HttpClientProtocol, @unchecked Sendable {
    /// Async access to the number of times *any* HTTP method was invoked.
    var calls: Int { get async { await tracker.current } }

    // MARK: – Init

    init<ResponseType>(result: Result<ResponseType, Error>)
        where ResponseType: Decodable & Sendable
    {
        resultBox = { try result.get() }
    }

    // MARK: – HttpClientProtocol

    nonisolated func post<B: Encodable, R: Decodable>(
        _: URL,
        body _: B,
        headers _: [String: String]? = nil
    ) async throws -> R {
        await record()
        return try fetch()
    }

    nonisolated func get<R: Decodable>(
        _: URL,
        headers _: [String: String]? = nil
    ) async throws -> R {
        await record()
        return try fetch()
    }

    // MARK: – Private

    private let tracker = CallTracker()
    /// Type-erased storage for the canned success / failure value.
    private let resultBox: () throws -> Any

    private func record() async { await tracker.bump() }

    private func fetch<R>() throws -> R {
        guard let value = try resultBox() as? R else {
            fatalError("Stub invoked with unexpected generic type \(R.self)")
        }
        return value
    }
}

// MARK: – Capturing stub for refresh-body assertions

private actor BodyStore {
    private var packets = [Data]()
    func record(_ data: Data) { packets.append(data) } //  Data is Sendable ✅
    var last: Data? { packets.last }
}

private final class CapturingHttpClient: HttpClientProtocol, @unchecked Sendable {
    private let store = BodyStore()
    private let tracker = CallTracker()
    private let resultBox: () throws -> Any

    init<Response: Decodable & Sendable>(result: Result<Response, Error>) {
        resultBox = { try result.get() }
    }

    nonisolated func post<B: Encodable, R: Decodable>(
        _: URL,
        body: B,
        headers _: [String: String]? = nil
    ) async throws -> R {
        await tracker.bump()

        // 🛡️  Copy to a Sendable container *before* crossing to the actor
        let payload = try JSONEncoder().encode(body)
        await store.record(payload)

        guard let value = try resultBox() as? R else {
            fatalError("Unexpected generic \(R.self)")
        }
        return value
    }

    nonisolated func get<R: Decodable>(
        _: URL,
        headers _: [String: String]? = nil
    ) async throws -> R {
        await tracker.bump()
        guard let value = try resultBox() as? R else { fatalError() }
        return value
    }

    // Helper for the test
    var latestJSON: [String: Any]? {
        get async {
            guard let data = await store.last else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    var calls: Int { get async { await tracker.current } }
}

// MARK: – Helper to build the System-Under-Test

private func makeSUT<H: HttpClientProtocol & Sendable>(
    authProvider: StubAuthProvider,
    http: H
) async throws -> AuthClient {
    let cfg = AuthClientConfig(
        authFunction: { try await authProvider.auth() },
        httpClient: http
    )
    return AuthClient(config: cfg)
}

// MARK: – Test-suite

@Suite
struct AuthClientTests {
    // -------------------------------------------------------------------------
    @Test("No cached payload → authFunction called once and token returned")
    func noPayload_invokesAuth() async throws {
        // GIVEN
        let expected = AuthPayload(
            accessToken: "token-A",
            refreshToken: "refresh-A",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() + 3600 * 1000
        )
        let auth = StubAuthProvider(result: .success(expected))
        let http = StubHttpClient(result: Result<AuthPayload, Error>.failure(URLError(.badURL)))
        let sut = try await makeSUT(authProvider: auth, http: http)

        // WHEN
        let token = try await sut.getAccessToken()

        // THEN
        #expect(token == expected.accessToken)
        #expect(await auth.calls == 1)
        #expect(await http.calls == 0)
    }

    // -------------------------------------------------------------------------
    @Test("Non-expired cached payload is reused – no extra auth / http hit")
    func cachedPayload_returnsImmediately() async throws {
        // GIVEN a stub that produces a fresh payload on first call
        let cached = AuthPayload(
            accessToken: "token-B",
            refreshToken: "refresh-B",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() + 3600 * 1000 // fresh
        )
        let auth = StubAuthProvider(result: .success(cached))
        let http = StubHttpClient(
            result: Result<AuthPayload, Error>.failure(AuthError.impossibleState))
        let sut = try await makeSUT(authProvider: auth, http: http)

        // Prime the cache (1st call)
        _ = try await sut.getAccessToken()

        // WHEN – 2nd call should *not* touch auth or http
        let token = try await sut.getAccessToken()

        // THEN
        #expect(token == cached.accessToken)
        #expect(await auth.calls == 1) // still 1
        #expect(await http.calls == 0)
    }

    // -------------------------------------------------------------------------
    @Test("Expired payload triggers refresh and returns new token")
    func expiredPayload_refreshes() async throws {
        // GIVEN an expired first payload and a refreshed one from the HTTP stub
        let expired = AuthPayload(
            accessToken: "old-token",
            refreshToken: "refresh-C",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() - 60 * 1000 // already expired
        )
        let refreshed = AuthPayload(
            accessToken: "new-token",
            refreshToken: "refresh-C2",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() + 3600 * 1000
        )
        let auth = StubAuthProvider(result: .success(expired))
        let http = StubHttpClient(result: .success(refreshed))
        let sut = try await makeSUT(authProvider: auth, http: http)

        // Prime with expired payload (1st call)
        _ = try await sut.getAccessToken()

        // WHEN – 2nd call should hit refresh
        let token = try await sut.getAccessToken()

        // THEN
        #expect(token == refreshed.accessToken)
        #expect(await auth.calls == 1) // no re-auth
        #expect(await http.calls == 1) // exactly one refresh
    }

    // -------------------------------------------------------------------------
    @Test("Refresh failure falls back to authFunction")
    func refreshFails_fallsBackToAuth() async throws {
        // First response: expired     Second response: fresh
        let expired = AuthPayload(
            accessToken: "old",
            refreshToken: "bad-refresh",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() - 3600 * 1000
        )

        let fresh = AuthPayload(
            accessToken: "fresh-token",
            refreshToken: "fresh-refresh",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() + 3600 * 1000
        )

        let auth = StubAuthProvider(
            responses: [.success(expired), .success(fresh)]
        )
        let http = StubHttpClient(
            result: Result<AuthPayload, Error>.failure(URLError(.badServerResponse))
        )
        let sut = try await makeSUT(authProvider: auth, http: http)

        // Prime with expired payload (1st call)
        _ = try await sut.getAccessToken()

        // WHEN – 2nd call: refresh fails → falls back to auth() again
        let token = try await sut.getAccessToken()

        // THEN
        #expect(token == fresh.accessToken)
        #expect(await http.calls == 1) // tried to refresh once
        #expect(await auth.calls == 2) // initial + fallback
    }

    // -------------------------------------------------------------------------
    @Test("Concurrent callers share the same in-flight auth task")
    func concurrentRequests_shareTask() async throws {
        let payload = AuthPayload(
            accessToken: "shared-token",
            refreshToken: "shared-refresh",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() + 3600 * 1000
        )
        let auth = StubAuthProvider(result: .success(payload))
        let http = StubHttpClient(
            result: Result<AuthPayload, Error>.failure(AuthError.impossibleState)
        )
        let sut = try await makeSUT(authProvider: auth, http: http)

        // WHEN – 10 concurrent requests before any cache exists
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0 ..< 10 {
                group.addTask { try await sut.getAccessToken() }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        // THEN
        #expect(Set(tokens) == [payload.accessToken]) // all identical
        #expect(await auth.calls == 1) // single flight
    }

    // -------------------------------------------------------------------------
    @Test("Refresh request sends refresh token in body")
    func refreshRequest_includesRefreshToken() async throws {
        // GIVEN – an expired payload so that the client must refresh
        let expired = AuthPayload(
            accessToken: "stale",
            refreshToken: "expected-refresh-token",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() - 1 // expired
        )
        let refreshed = AuthPayload(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            accessTokenExpiresAtUnixMs: currentUnixTimeMs() + 3600 * 1000
        )

        let auth = StubAuthProvider(result: .success(expired))
        let http = CapturingHttpClient(result: .success(refreshed))
        let sut = try await makeSUT(authProvider: auth, http: http)

        // Prime the cache (returns *expired* payload)
        _ = try await sut.getAccessToken()
        // 2nd call triggers the refresh POST
        _ = try await sut.getAccessToken()

        // THEN – the recorded POST body must contain the refresh token
        let json = await http.latestJSON
        #expect(json?["refreshToken"] as? String == expired.refreshToken)

        // …and still only one refresh hit
        #expect(await http.calls == 1)
    }

    // -------------------------------------------------------------------------
    @Test("AuthPayload decodes correctly from server JSON")
    func authPayload_decodesFromJSON() throws {
        // GIVEN – canonical server payload
        let expiryTimestamp = 1_725_000_000_000 // 2025-02-25 07:20:00 UTC in milliseconds
        let jsonString = """
        {
            "accessToken" : "json-access",
            "refreshToken": "json-refresh",
            "accessTokenExpiresAtUnixMs"   : \(expiryTimestamp)
        }
        """
        
        guard let json = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        // WHEN – decode using the same strategy your HttpClient uses
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase // mirror production

        let payload = try decoder.decode(AuthPayload.self, from: json)

        // THEN – every field must round-trip unchanged
        #expect(payload.accessToken == "json-access")
        #expect(payload.refreshToken == "json-refresh")
        #expect(payload.accessTokenExpiresAtUnixMs == expiryTimestamp)
    }
}
