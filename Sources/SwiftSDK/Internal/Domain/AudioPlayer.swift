import AVFoundation
import Combine
import Foundation

// MARK: - Core Types

public enum RepeatMode {
    case none
    case one
    case all
}

public enum PlayerEvent {
    case trackStarted(index: Int)
    case trackCompleted(index: Int)
    case playlistCompleted
    case errorOccurred(Error)
    case bufferingStateChanged(isBuffering: Bool)
    case airPlayStateChanged(isActive: Bool)
}

// MARK: - Player State

public struct PlayerState: Equatable {
    public enum PlaybackStatus: Equatable {
        case stopped
        case playing
        case paused
        case buffering
    }

    public let status: PlaybackStatus
    public let currentTime: TimeInterval
    public let totalTime: TimeInterval
    public let currentTrackIndex: Int
    public let totalTracks: Int
    public let repeatMode: RepeatMode

    public init(
        status: PlaybackStatus,
        currentTime: TimeInterval,
        totalTime: TimeInterval,
        currentTrackIndex: Int,
        totalTracks: Int,
        repeatMode: RepeatMode
    ) {
        self.status = status
        self.currentTime = currentTime
        self.totalTime = totalTime
        self.currentTrackIndex = currentTrackIndex
        self.totalTracks = totalTracks
        self.repeatMode = repeatMode
    }

    public var progress: Double {
        totalTime > 0 ? currentTime / totalTime : 0
    }

    public var remainingTime: TimeInterval {
        max(0, totalTime - currentTime)
    }

    public static func == (lhs: PlayerState, rhs: PlayerState) -> Bool {
        lhs.status == rhs.status && abs(lhs.currentTime - rhs.currentTime) < 0.5  // Allow small time differences
            && lhs.totalTime == rhs.totalTime && lhs.currentTrackIndex == rhs.currentTrackIndex
            && lhs.totalTracks == rhs.totalTracks && lhs.repeatMode == rhs.repeatMode
    }
}

// MARK: - Main Player Protocol

@MainActor
public protocol AudioPlayer: ObservableObject {
    /// Current player state - observe this for UI updates
    var state: PlayerState { get }

    /// Simple playing state for convenience
    var isPlaying: Bool { get }

    /// Events stream for one-time notifications
    var events: AnyPublisher<PlayerEvent, Never> { get }

    /// Start playing a playlist
    func play(playlist: PlaylistWithSongs) async

    /// Resume playback
    func resume()

    /// Pause playback
    func pause()

    /// Set repeat mode
    func setRepeatMode(_ mode: RepeatMode)

    /// Stop and cleanup
    func stop()
}

// MARK: - Convenience Extensions

extension AudioPlayer {
    /// Publisher that emits only when status changes
    public var statusPublisher: AnyPublisher<PlayerState.PlaybackStatus, Never> {
        events
            .compactMap { _ in nil as PlayerState.PlaybackStatus? }
            .prepend(state.status)
            .eraseToAnyPublisher()
    }

    /// Publisher for progress percentage (0.0 to 1.0)
    public var progressPublisher: AnyPublisher<Double, Never> {
        events
            .compactMap { _ in nil as Double? }
            .prepend(state.progress)
            .eraseToAnyPublisher()
    }
}

// MARK: - Error Types

public struct AudioPlayerError: LocalizedError {
    public let message: String

    public var errorDescription: String? { message }

    public static let emptyPlaylist = AudioPlayerError(message: "Cannot play an empty playlist")
    public static let invalidAudioURL = AudioPlayerError(message: "Invalid audio URL")
}
