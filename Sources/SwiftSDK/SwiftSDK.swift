func authFn() -> AuthPayload {
    return AuthPayload(
        accessToken: "", refreshToken: "", accessTokenExpiresAtUnixMs: 0
    )
}

protocol MyndSDKProtocol {
    var catalogue: CatalogueClientProtocol { get }
}

struct MyndSDK: MyndSDKProtocol {
    public let catalogue: CatalogueClientProtocol

    public init(
        authFunction: @Sendable @escaping () -> AuthPayloadProtocol,
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
