import struct Foundation.TimeInterval

public enum RepeatMode: Sendable {
    case none
    case loopSong
    case loopPlaylist
}

public enum PlaybackStatus: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(String)
}

public protocol ActiveSongProtocol: Sendable {
    var song: SongProtocol { get }
    var progress: TimeInterval { get }
    var index: Int { get }
}

public struct ActiveSong: ActiveSongProtocol, Sendable {
    public let song: SongProtocol
    public let progress: TimeInterval
    public let index: Int

    public init(song: SongProtocol, progress: TimeInterval, index: Int) {
        self.song = song
        self.progress = progress
        self.index = index
    }
}

public protocol PlayerStateProtocol: Sendable {
    var activeSong: ActiveSong? { get }
    var playbackStatus: PlaybackStatus { get }
    var repeatMode: RepeatMode { get }
    var volume: Float { get }
}

public struct PlayerState: PlayerStateProtocol, Sendable {
    public let activeSong: ActiveSong?
    public let playbackStatus: PlaybackStatus
    public let repeatMode: RepeatMode
    public let volume: Float

    public init(activeSong: ActiveSong?, activePlaylist _: PlaylistProtocol?, playbackStatus: PlaybackStatus, repeatMode: RepeatMode, volume: Float) {
        self.activeSong = activeSong
        self.playbackStatus = playbackStatus
        self.repeatMode = repeatMode
        self.volume = volume
    }
}

@MainActor
public protocol AudioPlayerProtocol: Sendable {
    var playerState: PlayerState { get }
    func startPlaylist(playlistWithSongs: PlaylistWithSongs) async
    func play()
    func pause()
    func destroy()
    func setRepeatMode(_ mode: RepeatMode)
}
