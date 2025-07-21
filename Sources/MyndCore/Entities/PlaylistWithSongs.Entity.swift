import Foundation

public protocol PlaylistWithSongsProtocol: Sendable {
    var playlist: Playlist { get }
    var songs: [Song] { get }
}

public struct PlaylistWithSongs: PlaylistWithSongsProtocol, Decodable, Sendable {
    public let playlist: Playlist
    public let songs: [Song]

    public init(playlist: Playlist, songs: [Song]) {
        self.playlist = playlist
        self.songs = songs
    }
}
