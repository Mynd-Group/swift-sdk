import Foundation



public protocol AuthPayloadProtocol: Sendable, Decodable, Encodable {
    var accessToken: String { get }
    var refreshToken: String { get }
    var accessTokenExpiresAtUnixMs: Int { get }
    var isExpired: Bool { get }
}

public struct AuthPayload: AuthPayloadProtocol, Decodable, Encodable {
    public let accessToken: String
    public let refreshToken: String
    public let accessTokenExpiresAtUnixMs: Int

    public init(accessToken: String, refreshToken: String, accessTokenExpiresAtUnixMs: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAtUnixMs = accessTokenExpiresAtUnixMs
    }

    public var isExpired: Bool {
        return accessTokenExpiresAtUnixMs < currentUnixTimeMs()
    }
}

protocol AuthClientProtocol: Sendable {
    func getAccessToken() async throws -> String
}

struct AuthClientConfig {
    public let refreshToken: String
    public let httpClient: HttpClientProtocol

    public init(
        refreshToken: String,
        httpClient: HttpClientProtocol
    ) {
        self.refreshToken = refreshToken
        self.httpClient = httpClient
    }
}

private let log = Logger(prefix: "AuthClient")
actor AuthClient: AuthClientProtocol {
    // MARK: – Dependencies

    private let httpClient: HttpClientProtocol
    private let refreshToken: String

    // MARK: – Cached state

    private var authPayload: AuthPayloadProtocol?
    private var authPayloadTask: Task<AuthPayloadProtocol, Error>? // in-flight refresh

    // MARK: – Init

    public init(config: AuthClientConfig) {
        httpClient = config.httpClient
        refreshToken = config.refreshToken
    }

    private func handleNoAuthPayload() async throws -> String {
        defer { authPayloadTask = nil }
        log.info("No auth payload, using initial refresh token")
        authPayloadTask = Task { () throws -> AuthPayloadProtocol in
            log.info("Using initial refresh token to get auth payload")
            let payload = try await self.getInitialAuthPayload()
            log.info("Initial refresh returned payload: \(payload)")
            return payload
        }
        guard let task = authPayloadTask else {
            log.error("Auth payload task is nil")
            throw AuthError.impossibleState
        }
        let payload = try await task.value
        authPayload = payload
        return try await handleValidAuthPayload()
    }

    private func handleExpiredAuthPayload() async throws -> String {
        defer { authPayloadTask = nil }
        log.info("Token is expired, refreshing")
        authPayloadTask = Task { () throws -> AuthPayloadProtocol in
            let payload = try await self.refreshAccessToken()
            guard let payload = payload else {
                log.error("Refresh token returned nil payload")
                throw AuthError.invalidRefreshToken
            }
            return payload
        }

        guard let task = authPayloadTask else {
            log.error("Auth payload task is nil in expired handler")
            throw AuthError.impossibleState
        }
        let payload = try await task.value
        authPayload = payload
        return try await handleValidAuthPayload()
    }

    private func handleOutstandingTask() async throws -> String {
        log.info("Outstanding task, waiting for it to finish")
        guard let task = authPayloadTask else {
            log.error("Auth payload task is nil in outstanding handler")
            throw AuthError.impossibleState
        }
        let payload = try await task.value
        authPayload = payload
        log.info("Task finished, returning token")
        return try await handleValidAuthPayload()
    }

    private func handleValidAuthPayload() async throws -> String {
        log.info("Token is not expired, returning token")
        guard let payload = authPayload else {
            log.error("Auth payload is nil when trying to get access token")
            throw AuthError.impossibleState
        }
        return payload.accessToken
    }

    // MARK: – Public

    public func getAccessToken() async throws -> String {
        // No auth payload
        if authPayloadTask == nil {
            let isAuthPayloadPresent = authPayload != nil

            if !isAuthPayloadPresent {
                return try await handleNoAuthPayload()
            }

            let isExpired = authPayload?.isExpired ?? false

            // Auth payload present but expired
            if isExpired {
                return try await handleExpiredAuthPayload()
            } else {
                return try await handleValidAuthPayload()
            }
        }

        return try await handleOutstandingTask()
    }

    // MARK: – Private helpers

    private func getInitialAuthPayload() async throws -> AuthPayloadProtocol {
        log.info("Getting initial auth payload with refresh token")
        return try await performRefreshTokenRequest(refreshToken: self.refreshToken)
    }

    private func refreshAccessToken() async throws -> AuthPayloadProtocol? {
        log.info("Refreshing access token")
        guard let currentPayload = authPayload else {
            log.info("No current payload")
            throw AuthError.invalidRefreshToken
        }

        log.info("Current payload: \(currentPayload)")
        return try await performRefreshTokenRequest(refreshToken: currentPayload.refreshToken)
    }

    private func performRefreshTokenRequest(refreshToken: String) async throws -> AuthPayloadProtocol {
        guard let url = URL(
            string: Config.baseUrl.appendingPathComponent("/integration-user/refresh-token")
                .absoluteString) else {
            log.error("Failed to create refresh token URL")
            throw AuthError.impossibleState
        }
        let headers = ["Content-Type": "application/json"]

        struct RefreshRequest: Encodable, Decodable {
            let refreshToken: String
        }

        do {
            let response: AuthPayload = try await httpClient.post(
                url, body: RefreshRequest(refreshToken: refreshToken),
                headers: headers
            )
            log.info("Response: \(response)")
            return response
        } catch URLError.badServerResponse {
            log.info("Bad server response")
            throw AuthError.invalidRefreshToken
        }
    }
}

// Optional helper error
enum AuthError: Error {
    case invalidRefreshToken
    case impossibleState
}
