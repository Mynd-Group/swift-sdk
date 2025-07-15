protocol SwiftSDKProtocol {
    var catalogue: CatalogueClientProtocol { get }
}

public struct SwiftSDK: SwiftSDKProtocol {
    public let catalogue: CatalogueClientProtocol

    public init(
        authFunction: @Sendable @escaping () async throws -> AuthPayloadProtocol,
    ) {
        let httpClient = HttpClient()
        let authClient = AuthClient(config: AuthClientConfig(
            authFunction: authFunction,
            httpClient: httpClient
        ))

        let authedHttpClient = AuthedHttpClient(config: AuthedHttpClientConfig(
            req: httpClient,
            authClient: authClient
        ))

        let catalogueConfig = CatalogueClientInfraConfig(
            authedHttpClient: authedHttpClient
        )

        catalogue = CatalogueClientInfraService(config: catalogueConfig)
    }
}
