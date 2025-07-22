import AVFoundation
import Combine
import Observation

extension Song {
  func toAVPlayerItem() async -> AVPlayerItem?  {
    guard let url = URL(string: self.audio.mp3.url) else { return nil }
    let asset = AVAsset(url: url)
    return await AVPlayerItem(asset: asset)
  }
}

extension PlaylistWithSongs {
  func toAvPlayerItems() async -> [AVPlayerItem] {
    await withTaskGroup(of: AVPlayerItem?.self) { group in
      // Add tasks for each song
      for song in self.songs {
        group.addTask {
          await song.toAVPlayerItem()
        }
      }

      // Collect results and filter out nils
      var playerItems: [AVPlayerItem] = []
      for await playerItem in group {
        if let playerItem = playerItem {
          playerItems.append(playerItem)
        }
      }
      return playerItems
    }
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

  public init(trackCurrentTime: TimeInterval, trackDuration: TimeInterval, trackIndex: Int, playlistCurrentTime: TimeInterval, playlistDuration: TimeInterval) {
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
  private var cancellables = Set<AnyCancellable>()
  private var progressObserver: Any?


  // MARK: - Lifecycle

  deinit {
    destroyPlayer()
  }

  // MARK: - Public Thread-Safe API
  @MainActor
  public func play(_ playlistWithSongs: PlaylistWithSongs) async {
    guard !playlistWithSongs.songs.isEmpty else {
      state = .stopped
      eventSubject.send(.errorOccurred(AudioError.emptyPlaylist))
      return
    }

    // Update observable state
    currentPlaylist = playlistWithSongs
    let p = playlistWithSongs
    await setupPlayer(with: p)

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
  public func stop() async {
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
  }

  public func setRepeatMode(_ mode: RepeatMode) {
    repeatMode = mode
  }

  @MainActor
  private func setupPlayer(with playlistWithSongs: PlaylistWithSongs) async {
    let items = await playlistWithSongs.toAvPlayerItems()

    guard !items.isEmpty else {
      state = .idle
      eventSubject.send(.errorOccurred(AudioError.emptyPlaylist))
      return
    }

    if player == nil {
      player = AVQueuePlayer()
      player?.automaticallyWaitsToMinimizeStalling = true
      setupObservers()
    }

    // Clear existing queue
    clearQueue()

    // Store references first
    playerItems = items

    // Reset tracking
    currentSongIndex = 0

    // Set initial playing state
    if let firstSong = playlistWithSongs.songs.first {
      currentSong = firstSong
      state = .playing(firstSong, index: 0)
      eventSubject.send(.stateChanged(state))
    }

    // add items to queue
    items.forEach { player?.insert($0, after: nil) }

    // Update progress
    updateProgressFromPlayer()

    // Only actually start playing if we're still in playing state
    // (user might have paused while items were loading)
    if case .playing = state {
      player?.play()
    }
  }

  @MainActor
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

  @MainActor
  private func handleItemDidPlayToEnd(_ item: AVPlayerItem)  {
    guard let playlist = currentPlaylist,
      currentSongIndex < playlist.songs.count
    else { return }

    let song = playlist.songs[currentSongIndex]
    eventSubject.send(.songCompleted(song, index: currentSongIndex))

    let isLastSong = currentSongIndex == playlist.songs.count - 1

    switch repeatMode {
    case .none:
      if isLastSong {
        state = .stopped
        eventSubject.send(.playlistCompleted)
        print("Playlist completed - stopping")
      } else {
        currentSongIndex += 1
        print("Moving to next song: \(currentSongIndex)")
      }

    case .all:
      if isLastSong {
        eventSubject.send(.playlistCompleted)
        print("Playlist completed - restarting for repeat all")
        Task{ await replayAllSongs() }
      } else {
        currentSongIndex += 1
        print("Moving to next song: \(currentSongIndex)")
      }
    }
  }

  private func handleCurrentItemChanged(_ item: AVPlayerItem) {
    guard let playlist = currentPlaylist,
      let player = player,
      let currentItem = player.currentItem,
      currentItem == item
    else { return }

    // Find the index of the current item in our playerItems array
    if let itemIndex = playerItems.firstIndex(of: item),
      itemIndex < playlist.songs.count
    {
      let song = playlist.songs[itemIndex]
      currentSong = song
      currentSongIndex = itemIndex

      if case .playing = state {
        state = .playing(song, index: itemIndex)
        eventSubject.send(.stateChanged(state))
      }
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
    else { return }

    let trackCurrentTime = currentItem.currentTime().seconds
    let trackDuration = TimeInterval(playlist.songs[index].audio.mp3.durationInSeconds)

    let (playlistCurrentTime, playlistDuration) = playlist.calculateProgress(
      currentTrackIndex: index,
      currentTrackTime: trackCurrentTime
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



  private func clearQueue() {
    guard let player = player else { return }

    let itemCount = playerItems.count
    print("Clearing queue with \(itemCount) items")

    // Remove all items from the queue
    player.removeAllItems()
    playerItems.removeAll()

    print("Queue cleared successfully")
  }

  @MainActor
  private func replayAllSongs() async {
    guard let playlist = currentPlaylist else { return }

    // Clear current queue and add all songs again
    clearQueue()
    let newItems = await playlist.toAvPlayerItems()
    newItems.forEach { player?.insert($0, after: nil) }

    // Update tracking
    playerItems = newItems
    currentSongIndex = 0
    if let firstSong = playlist.songs.first {
      currentSong = firstSong
    }

    player?.play()
  }

  private func destroyPlayer() {
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
