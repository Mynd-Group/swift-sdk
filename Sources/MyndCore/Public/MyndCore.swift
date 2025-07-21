import Combine
import AVFoundation

public final class MyndSDK {

    public let catalogue: CatalogueClientProtocol
    public let player:    AudioClientProtocol            

    public init(
        authFunction: @Sendable @escaping () async throws -> AuthPayloadProtocol,
        audioConfiguration: AudioClient.Configuration = .init()
    ) async {

        let httpClient   = HttpClient()
        let authClient   = AuthClient(
            config: .init(
                authFunction: authFunction,
                httpClient:   httpClient
            ))

        let authedHttpClient = AuthedHttpClient(
            config: .init(
                req:        httpClient,
                authClient: authClient
            ))

        let catalogueConfig = CatalogueClientInfraConfig(
            authedHttpClient: authedHttpClient
        )
        let catalogueService = CatalogueClientInfraService(config: catalogueConfig)
        self.catalogue = catalogueService


        self.player = await MainActor.run {
            AudioClient(configuration: audioConfiguration)
        }
    }
}
