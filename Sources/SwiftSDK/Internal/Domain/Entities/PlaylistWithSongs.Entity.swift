import Foundation

public protocol PlaylistWithSongsProtocol {
  var playlist: PlaylistProtocol { get }
  var songs: [SongProtocol] { get }
}

public struct PlaylistWithSongs: PlaylistWithSongsProtocol {
  public let playlist: PlaylistProtocol
  public let songs: [SongProtocol]

  public init(playlist: PlaylistProtocol, songs: [SongProtocol]) {
    self.playlist = playlist
    self.songs = songs
  }
}