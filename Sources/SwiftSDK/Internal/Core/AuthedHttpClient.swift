import Foundation

struct AuthedHttpClientConfig {
    let req: HttpClientProtocol
    let authClient: AuthClientProtocol
}

private let log = Logger(prefix: "AuthedHttpClient")
// TODO: ideally add retries on 401s and 5xxs
public struct AuthedHttpClient: HttpClientProtocol {
    private let req: HttpClientProtocol
    private let authClient: AuthClientProtocol

    init(
        config: AuthedHttpClientConfig
    ) {
        req = config.req
        authClient = config.authClient
    }

    public func get<R>(
        _ url: URL,
        headers: [String: String]? = nil
    ) async throws -> R where R: Decodable {
        let accessToken = try await authClient.getAccessToken()

        var authedheaders: [String: String] = headers ?? [:]
        authedheaders["Authorization"] = "Bearer \(accessToken)"
        log.info("GET \(url) with headers: \(authedheaders)")

        return try await req.get(url, headers: authedheaders)
    }

    public func post<B, R>(
        _ url: URL,
        body: B,
        headers: [String: String]? = nil
    ) async throws -> R where B: Encodable, R: Decodable {
        let accessToken = try await authClient.getAccessToken()

        var authedheaders: [String: String] = headers ?? [:]
        authedheaders["Authorization"] = "Bearer \(accessToken)"
        log.info("POST \(url) with headers: \(authedheaders) and body: \(body)")

        return try await req.post(url, body: body, headers: authedheaders)
    }
}
