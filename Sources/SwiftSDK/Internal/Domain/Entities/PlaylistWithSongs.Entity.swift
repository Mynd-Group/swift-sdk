import Foundation

public protocol PlaylistWithSongsProtocol {
    var playlist: Playlist { get }
    var songs: [Song] { get }
}

public struct PlaylistWithSongs: PlaylistWithSongsProtocol, Decodable {
    public let playlist: Playlist
    public let songs: [Song]

    public init(playlist: Playlist, songs: [Song]) {
        self.playlist = playlist
        self.songs = songs
    }
}

