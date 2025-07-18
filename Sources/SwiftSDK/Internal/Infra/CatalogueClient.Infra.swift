import Combine
import Foundation

public struct CatalogueClientInfraConfig {
    public let authedHttpClient: HttpClientProtocol
}

private let log = Logger(prefix: "CatalogueClient.Infra")
public struct CatalogueClientInfraService: CatalogueClientProtocol {
    private var authedHttpClient: HttpClientProtocol
    init(config: CatalogueClientInfraConfig) {
        authedHttpClient = config.authedHttpClient
    }

    public func getCategories() async throws -> [Category] {
        do {
            guard let url = URL(string: "\(Config.baseUrl)/integration/catalogue/categories") else {
                log.error("Failed to create categories URL")
                throw URLError(.badURL)
            }
            log.info("Fetching categories from URL: \(url)")
            let response: [Category] = try await authedHttpClient.get(url, headers: nil)
            log.info("Received categories: \(response.count) items")
            return response
        } catch {
            log.error("Failed to fetch categories: \(error)")
            throw error
        }
    }

    public func getCategory(categoryId: String) async throws -> Category {
        do {
            guard let url = URL(string: "\(Config.baseUrl)/integration/catalogue/categories/\(categoryId)") else {
                log.error("Failed to create category URL", dictionary: ["categoryId": categoryId])
                throw URLError(.badURL)
            }
            log.info("Fetching category from URL: \(url)")
            let response: Category = try await authedHttpClient.get(url, headers: nil)
            log.info("Received category: \(response.name)")
            return response
        } catch {
            log.error("Failed to fetch category with ID \(categoryId): \(error)")
            throw error
        }
    }

    public func getPlaylists(categoryId _: String?) async throws -> [Playlist] {
        do {
            guard let url = URL(string: "\(Config.baseUrl)/integration/catalogue/playlists") else {
                log.error("Failed to create playlists URL")
                throw URLError(.badURL)
            }
            log.info("Fetching playlists from URL: \(url)")
            let response: [Playlist] = try await authedHttpClient.get(url, headers: nil)
            log.info("Received playlists: \(response.count) items")
            return response
        } catch {
            log.error("Failed to fetch playlists: \(error)")
            throw error
        }
    }

    public func getPlaylist(playlistId: String) async throws -> PlaylistWithSongs {
        do {
            guard let url = URL(string: "\(Config.baseUrl)/integration/catalogue/playlists/\(playlistId)") else {
                log.error("Failed to create playlist URL", dictionary: ["playlistId": playlistId])
                throw URLError(.badURL)
            }
            log.info("Fetching playlist from URL: \(url)")
            let response: PlaylistWithSongs = try await authedHttpClient.get(url, headers: nil)
            log.info("Received playlist: \(response.playlist.name)")
            return response
        } catch {
            log.error("Failed to fetch playlist with ID \(playlistId): \(error)")
            throw error
        }
    }
}
