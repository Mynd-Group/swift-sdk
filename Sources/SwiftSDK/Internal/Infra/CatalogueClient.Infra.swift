import Combine
import Foundation

public struct CatalogueClientInfraConfig {
    public let authedHttpClient: HttpClientProtocol
}

public struct CatalogueClientInfra: CatalogueClientProtocol {
    private var authedHttpClient: HttpClientProtocol
    init(config: CatalogueClientInfraConfig) {
        authedHttpClient = config.authedHttpClient
    }

    public func getCategories() async throws -> [any CategoryProtocol] {
        let url = URL(string: "\(Config.baseUrl)/integration/catalogue/categories")!
        let response: [Category] = try await authedHttpClient.get(url, headers: nil)
        return response
    }

    public func getCategory(categoryId: String) async throws -> any CategoryProtocol {
        let url = URL(string: "\(Config.baseUrl)/integration/catalogue/categories/\(categoryId)")!
        let response: Category = try await authedHttpClient.get(url, headers: nil)
        return response
    }

    public func getPlaylists(categoryId _: String?) async throws -> [any PlaylistProtocol] {
        let url = URL(string: "\(Config.baseUrl)/integration/catalogue/playlists")!
        let response: [Playlist] = try await authedHttpClient.get(url, headers: nil)
        return response
    }

    public func getPlaylist(playlistId: String) async throws -> any PlaylistWithSongsProtocol {
        let url = URL(string: "\(Config.baseUrl)/integration/catalogue/playlists/\(playlistId)")!
        let response: PlaylistWithSongs = try await authedHttpClient.get(url, headers: nil)
        return response
    }
}
