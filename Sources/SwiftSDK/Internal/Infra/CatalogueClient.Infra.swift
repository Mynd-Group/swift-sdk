import Combine
import Foundation

public struct CatalogueClientInfraConfig {
    public let authedHttpClient: HttpClientProtocol
}

let log = Logger(prefix: "CatalogueClient.Infra")
public struct CatalogueClientInfraService: CatalogueClientProtocol {
    private var authedHttpClient: HttpClientProtocol
    init(config: CatalogueClientInfraConfig) {
        authedHttpClient = config.authedHttpClient
    }

    public func getCategories() async throws -> [any CategoryProtocol] {
        let url = URL(string: "\(Config.baseUrl)/integration/catalogue/categories")!
        log.info("Fetching categories from URL: \(url)")
        let response: [Category] = try await authedHttpClient.get(url, headers: nil)
        return response
    }

    public func getCategory(categoryId: String) async throws -> any CategoryProtocol {
        let url = URL(string: "\(Config.baseUrl)/integration/catalogue/categories/\(categoryId)")!
        log.info("Fetching category from URL: \(url)")
        let response: Category = try await authedHttpClient.get(url, headers: nil)
        return response
    }

    public func getPlaylists(categoryId _: String?) async throws -> [any PlaylistProtocol] {
        let url = URL(string: "\(Config.baseUrl)/integration/catalogue/playlists")!
        log.info("Fetching playlists from URL: \(url)")
        let response: [Playlist] = try await authedHttpClient.get(url, headers: nil)
        return response
    }

    public func getPlaylist(playlistId: String) async throws -> any PlaylistWithSongsProtocol {
        let url = URL(string: "\(Config.baseUrl)/integration/catalogue/playlists/\(playlistId)")!
        log.info("Fetching playlist from URL: \(url)")
        let response: PlaylistWithSongs = try await authedHttpClient.get(url, headers: nil)
        return response
    }
}
