import AVFoundation
import Combine
import Observation



public struct PlaybackProgress: Equatable {
    // Track-level progress
    public let trackCurrentTime: TimeInterval
    public let trackDuration: TimeInterval
    public let trackIndex: Int
    
    // Playlist-level progress
    public let playlistCurrentTime: TimeInterval
    public let playlistDuration: TimeInterval
    
    // Computed properties for track
    public var trackProgress: Double {
        trackDuration > 0 ? trackCurrentTime / trackDuration : 0
    }
    
    // Computed properties for playlist
    public var playlistProgress: Double {
        playlistDuration > 0 ? playlistCurrentTime / playlistDuration : 0
    }
}

public enum PlaybackState: Equatable {
    case idle
    case playing(Song, index: Int)
    case paused(Song, index: Int)
    case stopped
}

public enum RepeatMode: CaseIterable {
    case none
    case one
    case all
}

// MARK: - Events

public enum AudioPlayerEvent {
    case playlistQueued(PlaylistWithSongs)
    case stateChanged(PlaybackState)
    case progressUpdated(PlaybackProgress)
    case songCompleted(Song, index: Int)
    case playlistCompleted
    case errorOccurred(Error)
}

// MARK: - Audio Player Errors

public enum AudioError: LocalizedError {
    case emptyPlaylist
    case invalidURL(String)
    
    public var errorDescription: String? {
        switch self {
        case .emptyPlaylist:
            return "The playlist is empty"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        }
    }
}

// MARK: - Thread-Safe Audio Player

/// A thread-safe audio player that handles all MainActor requirements internally.
/// All public methods can be safely called from any thread.
@MainActor
public final class CoreAudioPlayer {
    // MARK: - Observable State (Thread-Safe)
    
    public private(set) var state: PlaybackState = .idle
    public private(set) var progress: PlaybackProgress = PlaybackProgress(
        trackCurrentTime: 0,
        trackDuration: 0,
        trackIndex: 0,
        playlistCurrentTime: 0,
        playlistDuration: 0
    )
    public private(set) var currentSong: Song?
    public private(set) var currentSongIndex: Int = 0
    public private(set) var currentPlaylist: PlaylistWithSongs?
    public var repeatMode: RepeatMode = .none
    
    // MARK: - Computed Properties
    
    public var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }
    
    // MARK: - Events Publisher
    
    private let eventSubject = PassthroughSubject<AudioPlayerEvent, Never>()
    public var events: AnyPublisher<AudioPlayerEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    
    private var player: AVQueuePlayer?
    private var playerItems: [AVPlayerItem] = []
    private var itemToSongMap: [AVPlayerItem: (song: Song, index: Int)] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var progressObserver: Any?
    private var songDurations: [Int: TimeInterval] = [:] // Cache song durations
    
    // MARK: - Private Concurrent Properties
    
    private let processingQueue = DispatchQueue(label: "com.audioPlayer.processing", qos: .userInitiated)
    
    // MARK: - Public Thread-Safe API
    
    /// Play a playlist with songs. Can be called from any thread.
    /// - Parameter playlistWithSongs: The playlist and its songs to play
    public func play(_ playlistWithSongs: PlaylistWithSongs) async {
        guard !playlistWithSongs.songs.isEmpty else {
            state = .stopped
            eventSubject.send(.errorOccurred(AudioError.emptyPlaylist))
            return
        }
        
        // Update observable state
        currentPlaylist = playlistWithSongs
        
        // Setup player
        setupPlayer(with: playlistWithSongs)
        
        eventSubject.send(.playlistQueued(playlistWithSongs))
    }
    
    /// Resume playback. Can be called from any thread.
    public func resume() {
        guard case .paused(let song, let index) = state else { return }
        player?.play()
        state = .playing(song, index: index)
        eventSubject.send(.stateChanged(state))
    }
    
    /// Pause playback. Can be called from any thread.
    public func pause() {
        guard case .playing(let song, let index) = state else { return }
        player?.pause()
        state = .paused(song, index: index)
        eventSubject.send(.stateChanged(state))
    }
    
    /// Stop playback and clear the playlist. Can be called from any thread.
    public func stop() async {
        cleanupPlayer()
        state = .stopped
        currentSong = nil
        currentSongIndex = 0
        progress = PlaybackProgress(
            trackCurrentTime: 0,
            trackDuration: 0,
            trackIndex: 0,
            playlistCurrentTime: 0,
            playlistDuration: 0
        )
        currentPlaylist = nil
        eventSubject.send(.stateChanged(state))
    }
    
    /// Seek to a specific time in the current track. Can be called from any thread.
    /// - Parameter time: Time in seconds to seek to
    public func seek(to time: TimeInterval) async {
        guard let currentItem = player?.currentItem else { return }
        await currentItem.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    /// Set the repeat mode. Can be called from any thread.
    /// - Parameter mode: The repeat mode to set
    public func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }
    
    // MARK: - Private Methods
    
    private func setupPlayer(with playlistWithSongs: PlaylistWithSongs) {
        // Clean up existing player
        cleanupPlayer()
        
        // Create player items and mapping
        var newItemToSongMap: [AVPlayerItem: (song: Song, index: Int)] = [:]
        let items: [AVPlayerItem] = playlistWithSongs.songs.enumerated().compactMap { index, song in
            guard let url = URL(string: song.audio.mp3.url) else {
                eventSubject.send(.errorOccurred(AudioError.invalidURL(song.audio.mp3.url)))
                return nil
            }
            
            let asset = AVAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            newItemToSongMap[item] = (song, index)
            return item
        }
        
        guard !items.isEmpty else {
            state = .idle
            eventSubject.send(.errorOccurred(AudioError.emptyPlaylist))
            return
        }
        
        // Store references
        playerItems = items
        itemToSongMap = newItemToSongMap
        
        // Create and configure player
        player = AVQueuePlayer(items: playerItems)
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.allowsExternalPlayback = true
        
        // Setup observers
        setupObservers()
        
        // Start playback
        player?.play()
    }
    
    private func setupObservers() {
        guard let player = player else { return }
        
        // Track item completion
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .compactMap { $0.object as? AVPlayerItem }
            .sink { [weak self] item in
                self?.handleItemDidPlayToEnd(item)
            }
            .store(in: &cancellables)
        
        // Track current item changes
        player.publisher(for: \.currentItem)
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] item in
                self?.handleCurrentItemChanged(item)
            }
            .store(in: &cancellables)
        
        // Track playback state changes
        player.publisher(for: \.timeControlStatus)
            .removeDuplicates()
            .sink { [weak self] status in
                self?.handleTimeControlStatusChanged(status)
            }
            .store(in: &cancellables)
        
        // Setup progress observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        progressObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgressFromPlayer()
            }
        }
    }
    
    private func handleItemDidPlayToEnd(_ item: AVPlayerItem) {
        guard let (song, index) = itemToSongMap[item] else { return }
        
        eventSubject.send(.songCompleted(song, index: index))
        
        switch repeatMode {
        case .none:
            if player?.items().isEmpty == true {
                state = .stopped
                eventSubject.send(.playlistCompleted)
            }
            
        case .one:
            Task {
                await item.seek(to: .zero)
                player?.play()
            }
            
        case .all:
            if player?.items().isEmpty == true {
                eventSubject.send(.playlistCompleted)
                replayAllSongs()
            }
        }
    }
    
    private func handleCurrentItemChanged(_ item: AVPlayerItem) {
        guard let (song, index) = itemToSongMap[item] else { return }
        
        currentSong = song
        currentSongIndex = index
        
        if case .playing = state {
            state = .playing(song, index: index)
            eventSubject.send(.stateChanged(state))
        }
    }
    
    private func handleTimeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        guard let song = currentSong else { return }
        
        let newState: PlaybackState = switch status {
        case .playing: .playing(song, index: currentSongIndex)
        case .paused: .paused(song, index: currentSongIndex)
        case .waitingToPlayAtSpecifiedRate: state // Keep current state while buffering
        @unknown default: state
        }
        
        if newState != state {
            state = newState
            eventSubject.send(.stateChanged(newState))
        }
    }
    
    private func updateProgressFromPlayer() {
        guard let currentItem = player?.currentItem,
              let (_, index) = itemToSongMap[currentItem] else { return }
        
        let trackCurrentTime = currentItem.currentTime().seconds
        
        Task {
            // Load duration asynchronously
            let trackDuration: TimeInterval
            if let cachedDuration = songDurations[index] {
                trackDuration = cachedDuration
            } else {
                
                  let duration = currentItem.asset.duration.seconds
                    trackDuration = duration
                    if !trackDuration.isNaN && !trackDuration.isInfinite {
                        songDurations[index] = trackDuration
                    }
                
            }
            
            if !trackCurrentTime.isNaN && !trackDuration.isNaN && !trackDuration.isInfinite {
                // Calculate playlist progress
                let (playlistCurrentTime, playlistDuration) = await calculatePlaylistProgress(
                    currentSongIndex: index,
                    currentSongTime: trackCurrentTime
                )
                
                let newProgress = PlaybackProgress(
                    trackCurrentTime: trackCurrentTime,
                    trackDuration: trackDuration,
                    trackIndex: index,
                    playlistCurrentTime: playlistCurrentTime,
                    playlistDuration: playlistDuration
                )
                
                if newProgress != progress {
                    progress = newProgress
                    eventSubject.send(.progressUpdated(newProgress))
                }
            }
        }
    }
    
    private func calculatePlaylistProgress(currentSongIndex: Int, currentSongTime: TimeInterval) async -> (current: TimeInterval, total: TimeInterval) {
        var playlistCurrentTime: TimeInterval = 0
        var playlistDuration: TimeInterval = 0
        
        // Calculate total duration and time up to current song
        for (index, item) in playerItems.enumerated() {
            let duration: TimeInterval
            if let cachedDuration = songDurations[index] {
                duration = cachedDuration
            } else {
                
                  let assetDuration = item.asset.duration.seconds
                    duration = assetDuration
                    if !duration.isNaN && !duration.isInfinite {
                        songDurations[index] = duration
                    }
              
            }
            
            if !duration.isNaN && !duration.isInfinite {
                playlistDuration += duration
                
                if index < currentSongIndex {
                    // Add full duration of completed songs
                    playlistCurrentTime += duration
                } else if index == currentSongIndex {
                    // Add current time of current song
                    playlistCurrentTime += currentSongTime
                }
            }
        }
        
        return (playlistCurrentTime, playlistDuration)
    }
    
    private func replayAllSongs() {
        // Create new items for all songs
        guard let playlist = currentPlaylist else { return }
        
        var newItemToSongMap: [AVPlayerItem: (song: Song, index: Int)] = [:]
        
        let newItems: [AVPlayerItem] = playlist.songs.enumerated().compactMap { index, song in
            guard let url = URL(string: song.audio.mp3.url) else { return nil }
            let item = AVPlayerItem(asset: AVAsset(url: url))
            newItemToSongMap[item] = (song, index)
            return item
        }
        
        // Update mapping and add to queue
        itemToSongMap = newItemToSongMap
        newItems.forEach { player?.insert($0, after: nil) }
        
        player?.play()
    }
    
    private func cleanupPlayer() {
        if let observer = progressObserver {
            player?.removeTimeObserver(observer)
            progressObserver = nil
        }
        
        player?.pause()
        player = nil
        playerItems.removeAll()
        itemToSongMap.removeAll()
        cancellables.removeAll()
        songDurations.removeAll()
    }
}


