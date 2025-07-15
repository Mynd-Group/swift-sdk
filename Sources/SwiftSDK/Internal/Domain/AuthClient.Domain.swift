/* import Foundation

public protocol AuthPayloadProtocol {
    var accessToken: String { get }
    var refreshToken: String { get }
    var expiresAt: Date { get }
    var isExpired: Bool { get }
}

public struct AuthPayload: AuthPayloadProtocol {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        return expiresAt < Date()
    }
}

public protocol AuthClientProtocol {
    func getAccessToken() async throws -> String
}

public struct AuthClient: AuthClientProtocol {
    public func getAccessToken() async throws -> String {
        return ""
    }
} */