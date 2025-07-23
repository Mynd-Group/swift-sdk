import AVFoundation
import Combine
import Observation

func songToAvPlayerItem(_ song: Song) async -> AVPlayerItem? {
    guard let url = URL(string: song.audio.mp3.url) else { return nil }
    
    // Create asset on background thread
    let asset = AVURLAsset(url: url)
    
    // Must create AVPlayerItem on MainActor
    return await MainActor.run {
        AVPlayerItem(asset: asset)
    }
}

/// Converts every `Song` in the playlist to an `AVPlayerItem`,
/// launching at most 30 concurrent conversions.
func playlistToAvPlayerItems(_ playlist: PlaylistWithSongs) async -> [AVPlayerItem] {
  log.info(">>> Converting playlist to AVPlayerItems")
    let songs      = playlist.songs
    let batchSize  = 30
    var allResults = Array<(Int, AVPlayerItem?)>()          // (original index, item)
    allResults.reserveCapacity(songs.count)

    // Move through the array in strides of `batchSize`
    for batchStart in stride(from: 0, to: songs.count, by: batchSize) {
        let batchEnd = min(batchStart + batchSize, songs.count)
        let slice    = songs[batchStart..<batchEnd]

        // Convert this 30‑song slice in parallel
        let batchResults: [(Int, AVPlayerItem?)] = await withTaskGroup(
            of: (Int, AVPlayerItem?).self
        ) { group in
          log.info(">>> Processing batch \(batchStart)/\(batchEnd)")
            for (offset, song) in slice.enumerated() {
                let globalIndex = batchStart + offset      // keep original position
                group.addTask {
                    let item = await songToAvPlayerItem(song)
                    return (globalIndex, item)
                }
            }

            // Collect results for this batch
            var results = [(Int, AVPlayerItem?)]()
            for await result in group { results.append(result) }
            log.info(">>> Batch \(batchStart)/\(batchEnd) done")
            return results
        }

        allResults.append(contentsOf: batchResults)
    }

    // Restore the original playlist order and strip the optionals
    allResults.sort { $0.0 < $1.0 }
  log.info(">>> Done converting playlist to AVPlayerItems")
    return allResults.compactMap { $0.1 }
}


extension Song {
  @MainActor
  func toAVPlayerItem() -> AVPlayerItem? {
    guard let url = URL(string: self.audio.mp3.url) else { return nil }
    let asset = AVURLAsset(url: url)
    
    return AVPlayerItem(asset: asset)
  }

  func toAVAsset() -> AVAsset? {
    guard let url = URL(string: self.audio.mp3.url) else { return nil }
    let asset = AVAsset(url: url)
    return asset
  }
}

extension PlaylistWithSongs {
  func toAvPlayerItems() async -> [AVPlayerItem] {
   return await playlistToAvPlayerItems(self)
  }

  func calculateProgress(
    currentTrackIndex: Int,
    currentTrackTime: TimeInterval
  ) -> (currentTime: TimeInterval, totalDuration: TimeInterval) {
    var playlistCurrentTime: TimeInterval = 0
    var playlistTotalDuration: TimeInterval = 0

    for (index, song) in songs.enumerated() {
      let songDuration = TimeInterval(song.audio.mp3.durationInSeconds)
      playlistTotalDuration += songDuration

      if index < currentTrackIndex {
        playlistCurrentTime += songDuration
      } else if index == currentTrackIndex {
        playlistCurrentTime += currentTrackTime
      }
    }

    return (playlistCurrentTime, playlistTotalDuration)
  }
}

public struct PlaybackProgress: Equatable {
  // Track-level progress
  public let trackCurrentTime: TimeInterval
  public let trackDuration: TimeInterval
  public let trackIndex: Int

  // Playlist-level progress
  public let playlistCurrentTime: TimeInterval
  public let playlistDuration: TimeInterval

  public init(
    trackCurrentTime: TimeInterval,
    trackDuration: TimeInterval,
    trackIndex: Int,
    playlistCurrentTime: TimeInterval,
    playlistDuration: TimeInterval
  ) {
    self.trackCurrentTime = trackCurrentTime
    self.trackDuration = trackDuration
    self.trackIndex = trackIndex
    self.playlistCurrentTime = playlistCurrentTime
    self.playlistDuration = playlistDuration
  }

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
  case all
}

// MARK: - Events

public enum AudioPlayerEvent {
  case playlistQueued(PlaylistWithSongs)
  case stateChanged(PlaybackState)
  case progressUpdated(PlaybackProgress)
  case songCompleted(Song, index: Int)
  case playlistCompleted
  case songNetworkStalled
  case songNetworkFailure(Error)
  case errorOccurred(Error)
  case volumeChanged(Float)
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

private let log = Logger(prefix: "CoreAudioPlayer")
public final class CoreAudioPlayer {

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
  private(set) var volume: Float = 1.0

  // MARK: - Computed Properties

  public var isPlaying: Bool {
    if case .playing = state { return true }
    return false
  }

  // MARK: - Volume Control

  public func setVolume(_ newValue: Float) {
    guard newValue >= 0.0, newValue <= 1.0 else {
      log.info("Volume out of bounds: \(newValue)")
      return
    }
    if volume != newValue {
      volume = newValue
      if let player = player {
        player.volume = newValue
      }
      log.info("Volume set to \(newValue)")
      eventSubject.send(.volumeChanged(newValue))
    }
  }

  // MARK: - Events Publisher

  private let eventSubject = PassthroughSubject<AudioPlayerEvent, Never>()
  public var events: AnyPublisher<AudioPlayerEvent, Never> {
    eventSubject.eraseToAnyPublisher()
  }

  // MARK: - Private Properties

  private var player: AVQueuePlayer?
  private var playerItems: [AVPlayerItem] = []
  private var cancellables = Set<AnyCancellable>()
  private var progressObserver: Any?

  // MARK: - Lifecycle

  deinit {
    destroyPlayer()
  }

  // MARK: - Public Thread-Safe API
  @MainActor
  public func play(_ playlistWithSongs: PlaylistWithSongs) async {
    log.info(">>> Playlist selected \(playlistWithSongs.playlist.name) <<<")
    guard !playlistWithSongs.songs.isEmpty else {
      state = .stopped
      eventSubject.send(.errorOccurred(AudioError.emptyPlaylist))
      return
    }

    // Update observable state
    currentPlaylist = playlistWithSongs
    let p = playlistWithSongs
    log.info("Setting up player...")
    await setupPlayer(with: p)
    log.info(">>> Playlist setup completed <<<")

    eventSubject.send(.playlistQueued(playlistWithSongs))
  }

  @MainActor
  public func resume() {
    guard case .paused(let song, let index) = state else { return }
    player?.play()
    state = .playing(song, index: index)
    eventSubject.send(.stateChanged(state))
  }

  @MainActor
  public func pause() {
    guard case .playing(let song, let index) = state else { return }
    player?.pause()
    state = .paused(song, index: index)
    eventSubject.send(.stateChanged(state))
  }

  @MainActor
  public func stop() {
    player?.pause()
    clearQueue()

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
    log.info(">>> Player stopped <<<")

  }

  public func setRepeatMode(_ mode: RepeatMode) {
    repeatMode = mode
  }

  @MainActor
  private func setupPlayer(with playlistWithSongs: PlaylistWithSongs) async {
      log.info(">>> Setting up player... <<<")
      guard !playlistWithSongs.songs.isEmpty else {
          state = .idle
          eventSubject.send(.errorOccurred(AudioError.emptyPlaylist))
          return
      }
      
      log.info("Converting songs to AVPlayerItems...")
      let items = await playlistWithSongs.toAvPlayerItems()
      log.info(">>> \(items.count) items converted <<<")
      
      if player == nil {
          player = AVQueuePlayer()
          player?.automaticallyWaitsToMinimizeStalling = true
          player?.volume = volume
          setupObservers()
      } else {
          
          clearQueue()
      }

      playerItems = items
      currentSongIndex = 0

      if let firstSong = playlistWithSongs.songs.first {
          currentSong = firstSong
          state = .playing(firstSong, index: 0)
          eventSubject.send(.stateChanged(state))
      }

      // Add items to queue
      if let player = player, !items.isEmpty {
  
          
        log.info("Queuing first item")
        // Queue first few items on main thread
        player.replaceCurrentItem(with: items[0])
        log.info(">>> Queued initial item <<<")
    
        
          
          // Queue remaining items in background and wait for completion
          
              let remainingItems = Array(items.dropFirst())
              updateProgressFromPlayer()
              let capturedPreviousItem = items[0]
              let itemCount = remainingItems.count
              
            await Task.detached(priority: .userInitiated) {
                  log.info("inserting remaining \(itemCount) items...")
                  var previous = capturedPreviousItem
                  
                  for (index, item) in remainingItems.enumerated() {
                      player.insert(item, after: previous)
                      previous = item
                  }
                  
                log.info("Finished queueing remaining \(itemCount) items")
              }.value
          
          
          log.info("All player items queued")
      }
      
      player?.play()
      updateProgressFromPlayer()
      log.info(">>> Player setup complete <<<")
  }
  
  @MainActor
  private func setupObservers() {
    log.info("Setting up observers")
    guard let player = player else { return }

    // Track item completion
    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
      .receive(on: DispatchQueue.main)
      .compactMap { $0.object as? AVPlayerItem }
      .sink { [weak self] item in
        self?.handleItemDidPlayToEnd(item)
      }
      .store(in: &cancellables)

    // Track item network stall
    NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled)
      .receive(on: DispatchQueue.main)
      .compactMap { $0.object as? AVPlayerItem }
      .sink { [weak self] item in
        self?.handlePlaybackStalled(item)
      }
      .store(in: &cancellables)

    // Track item network unrecoverable failure
    NotificationCenter.default.publisher(
      for: .AVPlayerItemFailedToPlayToEndTime
    )
    .receive(on: DispatchQueue.main)
    .compactMap { $0.object as? AVPlayerItem }
    .sink { [weak self] item in
      self?.handlePlaybackFailed(item)
    }
    .store(in: &cancellables)

    // Track current item changes
    player.publisher(for: \.currentItem)
      .receive(on: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] item in
        self?.handleCurrentItemChanged(item)
      }
      .store(in: &cancellables)

    // Track playback state changes
    player.publisher(for: \.timeControlStatus)
      .receive(on: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] status in
        self?.handleTimeControlStatusChanged(status)
      }
      .store(in: &cancellables)

    // Setup progress observer
    let interval = CMTime(seconds: 0.33, preferredTimescale: 600)
    progressObserver = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.updateProgressFromPlayer()
      }
    }
  }

  private func handlePlaybackStalled(_ item: AVPlayerItem) {
    log.info("Playback stalled - buffering...")
    eventSubject.send(.songNetworkStalled)
  }

  @MainActor
  private func handlePlaybackFailed(_ item: AVPlayerItem) {
    if let error = item.error {
      log.error("Playback failed: \(error)")
      eventSubject.send(.songNetworkFailure(error))
      pause()
    }
  }

  @MainActor
  private func handleItemDidPlayToEnd(_ item: AVPlayerItem) {
    log.info("Item played to end")
    guard let playlist = currentPlaylist,
      let itemIndex = playerItems.firstIndex(of: item),
      itemIndex < playlist.songs.count
    else { return }

    let song = playlist.songs[itemIndex]
    eventSubject.send(.songCompleted(song, index: itemIndex))

    let isLastSong = itemIndex == playlist.songs.count - 1

    switch repeatMode {
    case .none:
      if isLastSong {
        eventSubject.send(.playlistCompleted)
        log.info("Playlist completed - stopping")
        stop()
      } else {
        // AVQueuePlayer automatically advances to next item
        log.info("Song \(itemIndex) completed, advancing to next")
      }

    case .all:
      if isLastSong {
        eventSubject.send(.playlistCompleted)
        log.info("Playlist completed - restarting for repeat all")
        Task {
          await replayAllSongs()
        }
      } else {
        // AVQueuePlayer automatically advances to next item
        log.info("Song \(itemIndex) completed, advancing to next")
      }
    }
  }

  @MainActor
  private func handleCurrentItemChanged(_ item: AVPlayerItem?) {
    log.info("Current Item Changed")
    guard let item = item else {
      log.info("🚧 Current item is nil")
      currentSong = nil
      return
    }

    guard let playlist = currentPlaylist,
      let itemIndex = playerItems.firstIndex(of: item),
      itemIndex < playlist.songs.count
    else {
      log.info("Could not find item in playerItems or index out of bounds")
      return
    }

    let song = playlist.songs[itemIndex]
    log.info(
      "🎵 Current item changed to index \(itemIndex): \(song.name ?? "Unknown")"
    )

    // ALWAYS update these
    currentSong = song
    currentSongIndex = itemIndex

    // Update state based on player status
    switch player?.timeControlStatus {
    case .playing:
      state = .playing(song, index: itemIndex)
      eventSubject.send(.stateChanged(state))
    case .paused:
      state = .paused(song, index: itemIndex)
      eventSubject.send(.stateChanged(state))
    default:
      break
    }
  }

  private func handleTimeControlStatusChanged(
    _ status: AVPlayer.TimeControlStatus
  ) {
    guard let song = currentSong else { return }

    let newState: PlaybackState =
      switch status {
      case .playing: .playing(song, index: currentSongIndex)
      case .paused: .paused(song, index: currentSongIndex)
      case .waitingToPlayAtSpecifiedRate: state  // Keep current state while buffering
      @unknown default: state
      }

    if newState != state {
      state = newState
      eventSubject.send(.stateChanged(newState))
    }
  }

  @MainActor
  private func updateProgressFromPlayer() {
    guard let currentItem = player?.currentItem,
      let playlist = currentPlaylist,
      let index = playerItems.firstIndex(of: currentItem),
      index < playlist.songs.count
    else {
      log.warn("Cannot update progress from player condition not met")

      return
    }

    let trackCurrentTime = currentItem.currentTime().seconds
    let trackDuration = currentItem.duration

    // Use the actual item index, not currentSongIndex
    let (playlistCurrentTime, playlistDuration) = playlist.calculateProgress(
      currentTrackIndex: index,
      currentTrackTime: trackCurrentTime
    )

    let newProgress = PlaybackProgress(
      trackCurrentTime: trackCurrentTime,
      trackDuration: trackDuration.seconds,
      trackIndex: index,
      playlistCurrentTime: playlistCurrentTime,
      playlistDuration: playlistDuration
    )

    if newProgress != progress {
      progress = newProgress
      eventSubject.send(.progressUpdated(newProgress))
    }
  }

  private func clearQueue()  {
    log.info( "Clearing queue")
      // Remove all items from the queue
      player?.removeAllItems()
      playerItems.removeAll()
      
      log.info("Queue cleared successfully")
    
  }

  @MainActor
  private func replayAllSongs() async {
    log.info("Replaying all songs")
    guard let playlist = currentPlaylist else { return }

    // Clear current queue and add all songs again
    await clearQueue()
    let newItems = await playlist.toAvPlayerItems()
    newItems.forEach { player?.insert($0, after: nil) }

    // Update tracking
    playerItems = newItems
    currentSongIndex = 0
    if let firstSong = playlist.songs.first {
      currentSong = firstSong
      state = .playing(firstSong, index: 0)
      eventSubject.send(.stateChanged(state))
    }

    player?.play()
  }

  private func destroyPlayer() {
    log.info("Destroy player")
    cancellables.removeAll()

    if let observer = progressObserver {
      player?.removeTimeObserver(observer)
      progressObserver = nil
    }

    // Handle main actor-isolated calls
    if let player = player {
      Task { @MainActor in
        player.pause()
      }
    }

    player = nil
    playerItems.removeAll()
  }
}
