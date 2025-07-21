import Combine

public final class SwiftSDK: ObservableObject {
    public let catalogue: CatalogueClientProtocol
    @Published public var player: any AudioPlayer

    private var cancellables = Set<AnyCancellable>()

    @MainActor
    public static func create(
        authFunction: @Sendable @escaping () async throws -> AuthPayloadProtocol
    ) async -> SwiftSDK {
        let httpClient = HttpClient()

        let authClient = AuthClient(
            config: AuthClientConfig(
                authFunction: authFunction,
                httpClient: httpClient
            ))

        let authedHttpClient = AuthedHttpClient(
            config: AuthedHttpClientConfig(
                req: httpClient,
                authClient: authClient
            ))

        let catalogueConfig = CatalogueClientInfraConfig(
            authedHttpClient: authedHttpClient
        )

        let catalogue = CatalogueClientInfraService(config: catalogueConfig)
        let player = AudioPlayerService()

        return SwiftSDK(catalogue: catalogue, player: player)
    }

    private init(catalogue: CatalogueClientProtocol, player: any AudioPlayer) {
        self.catalogue = catalogue
        self.player = player

        // Forward player changes to this ObservableObject
        if let audioPlayerService = player as? AudioPlayerService {
            audioPlayerService.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }
}
