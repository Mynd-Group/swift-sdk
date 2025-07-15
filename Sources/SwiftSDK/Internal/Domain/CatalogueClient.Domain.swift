import Foundation

public protocol CatalogueClientProtocol: Sendable {
    func getCategories() async throws -> [CategoryProtocol]
    func getCategory(categoryId: String) async throws -> CategoryProtocol
    func getPlaylists(categoryId: String?) async throws -> [PlaylistProtocol]
    func getPlaylist(playlistId: String) async throws -> PlaylistWithSongsProtocol
}
