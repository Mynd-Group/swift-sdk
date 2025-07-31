import Combine
import AVFoundation

public final class MyndSDK {
    public let catalogue: CatalogueClientProtocol
    public let player: AudioClientProtocol
    
    @MainActor
    public init(
        refreshToken: String,
        audioConfiguration: AudioClient.Configuration = .init()
    ) {
        let httpClient   = HttpClient()
        let authClient   = AuthClient(
            config: .init(
                refreshToken: refreshToken,
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
        self.player = AudioClient(configuration: audioConfiguration)
    }
}
