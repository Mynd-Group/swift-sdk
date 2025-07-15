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

public struct AuthClientConfig {
    public let authFunction: @Sendable () async throws -> AuthPayloadProtocol
    public let httpClient: HttpClientProtocol

    public init(
        authFunction: @Sendable @escaping () async throws -> AuthPayloadProtocol,
        httpClient: HttpClientProtocol
    ) {
        self.authFunction = authFunction
        self.httpClient = httpClient
    }
}

public actor AuthClient: AuthClientProtocol {
    // MARK: – Dependencies

    private let httpClient: HttpClientProtocol
    private let authFunction: @Sendable () async throws -> AuthPayloadProtocol

    // MARK: – Cached state

    private var authPayload: AuthPayloadProtocol?
    private var authPayloadTask: Task<AuthPayloadProtocol, Error>? // in-flight refresh

    // MARK: – Init

    public init(config: AuthClientConfig) async throws {
        httpClient = config.httpClient
        authFunction = config.authFunction
    }

    private func handleNoAuthPayload() async throws -> String {
        defer { authPayloadTask = nil }
        print("No auth data, using auth function")
        authPayloadTask = Task { () throws -> AuthPayloadProtocol in
            print("Launching auth function")
            let payload = try await self.authFunction()
            print("Auth function returned payload: \(payload)")
            return payload
        }
        let payload = try await authPayloadTask!.value
        authPayload = payload
        return try await handleValidAuthPayload()
    }

    private func handleExpiredAuthPayload() async throws -> String {
        defer { authPayloadTask = nil }
        print("Token is expired, refreshing")
        authPayloadTask = Task { () throws -> AuthPayloadProtocol in
            do {
                let payload = try await self.refreshAccessToken()
                return payload!
            } catch {
                // TODO: we should only do this on some errors
                do {
                    let payload = try await self.authFunction()
                    return payload
                } catch {
                    throw error
                }
            }
        }

        let payload = try await authPayloadTask!.value
        authPayload = payload
        return try await handleValidAuthPayload()
    }

    private func handleOutstandingTask() async throws -> String {
        print("Outstanding task, waiting for it to finish")
        let payload = try await authPayloadTask!.value
        authPayload = payload
        print("Task finished, returning token")
        return try await handleValidAuthPayload()
    }

    private func handleValidAuthPayload() async throws -> String {
        print("Token is not expired, returning token")
        return authPayload!.accessToken
    }

    // MARK: – Public

    public func getAccessToken() async throws -> String {
        // No auth payload
        if authPayloadTask == nil {
            let isAuthPayloadPresent = authPayload != nil

            if !isAuthPayloadPresent {
                return try await handleNoAuthPayload()
            }

            let isExpired = authPayload != nil && authPayload!.isExpired

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

    private func refreshAccessToken() async throws -> AuthPayloadProtocol? {
        print("Refreshing access token")
        guard let currentPayload = authPayload else {
            print("No current payload")
            throw AuthError.invalidRefreshToken
        }

        print("Current payload: \(currentPayload)")

        let url = URL(
            string: Config.baseUrl.appendingPathComponent("/integration-user/auth/refresh")
                .absoluteString)!
        let headers = ["Content-Type": "application/json"]
        print("Headers: \(headers)")
        print("URL: \(url)")

        struct RefreshRequest: Encodable, Decodable {
            let refresh_token: String
        }

        do {
            let response: AuthPayload = try await httpClient.post(
                url, body: RefreshRequest(refresh_token: currentPayload.refreshToken),
                headers: headers
            )
            print("Response: \(response)")
            return response
        } catch URLError.badServerResponse {
            print("Bad server response")
            throw AuthError.invalidRefreshToken
        }
    }
}

// Optional helper error
enum AuthError: Error {
    case invalidRefreshToken
    case impossibleState
}
