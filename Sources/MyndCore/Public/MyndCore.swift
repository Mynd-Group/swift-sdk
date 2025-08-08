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
  
  public func setCurrentMood(_ mood: Float) async throws {
    if (mood < 0){
      throw NSError(domain: "Mood must be between 0 and 1", code: 1001)
    } else if (mood > 1){
      throw NSError(domain: "Mood must be between 0 and 1", code: 1001)
    }
    
    // TODO: implement
    return
  }
  
  public func rateListeningSession(_ rating: Float) async throws {
    if (rating < 0){
      throw NSError(domain: "Rating must be between 0 and 1", code: 1001)
    } else if (rating > 1){
      throw NSError(domain: "Rating must be between 0 and 1", code: 1001)
    }
    
    // TODO: implement
    return
  }
}
