import Foundation

public protocol CatalogueClientProtocol: Sendable {
    func getCategories() async throws -> [Category]
    func getCategory(categoryId: String) async throws -> Category
    func getPlaylists(categoryId: String?) async throws -> [Playlist]
    func getPlaylist(playlistId: String) async throws -> PlaylistWithSongs
}
