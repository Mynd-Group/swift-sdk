import AVFoundation
import Combine
import Observation

func makeAssetsPlayable(_ assets: [AVURLAsset]) async -> [AVURLAsset] {
  return await withTaskGroup(of: (Int, AVURLAsset).self, returning: [AVURLAsset].self)
  { group in
    for (index, asset) in assets.enumerated() {
      group.addTask {
        await withCheckedContinuation { continuation in
          asset.loadValuesAsynchronously(forKeys: [
            "playable", "duration", "tracks",
          ]) {
            continuation.resume(returning: (index, asset))
          }
        }
      }
    }

    var indexedResults: [(Int, AVURLAsset)] = []
    for await result in group {
      indexedResults.append(result)
    }

    return indexedResults
      .sorted { $0.0 < $1.0 }
      .map { $0.1 }
  }
}

func songsToAssets(_ songs: [Song]) async -> [AVURLAsset] {
  return await Task.detached(priority: .userInitiated) {
    let urls: [URL] = songs.compactMap { URL(string: $0.audio.mp3.url) }
    let assets = urls.map { AVURLAsset(url: $0) }
    return assets
  }.value
}

func assetsToItems(_ assets: [AVURLAsset]) -> [AVPlayerItem] {
  return assets.map { AVPlayerItem(asset: $0) }
}

func songsToPlayerItems(_ songs: [Song]) async -> [AVPlayerItem] {
  return await Task.detached(priority: .userInitiated) {
    let urls: [String] = songs.compactMap { $0.audio.mp3.url }

    let items: [AVPlayerItem] = await withTaskGroup(
      of: (Int, AVPlayerItem?).self
    ) { group in
      for (index, urlString) in urls.enumerated() {
        group.addTask {
          guard let url = URL(string: urlString) else { return (index, nil) }
          let asset = AVURLAsset(url: url)

          await withCheckedContinuation { continuation in
            asset.loadValuesAsynchronously(forKeys: ["playable"]) {
              continuation.resume()
            }
          }

          return (index, AVPlayerItem(asset: asset))
        }
      }

      var indexedItems: [(Int, AVPlayerItem?)] = []
      for await result in group {
        indexedItems.append(result)
      }

      return
        indexedItems
        .sorted { $0.0 < $1.0 }
        .compactMap { $0.1 }
    }

    return items
  }.value
}

func playlistToAvPlayerItems(_ playlist: PlaylistWithSongs) async
  -> [AVPlayerItem]
{
  let result = await songsToPlayerItems(playlist.songs)
  return result
}

extension PlaylistWithSongs {
  func toAvPlayerItems() async -> [AVPlayerItem] {
    let result = await playlistToAvPlayerItems(self)
    return result
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
  public let trackCurrentTime: TimeInterval
  public let trackDuration: TimeInterval
  public let trackIndex: Int

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

  public var trackProgress: Double {
    trackDuration > 0 ? trackCurrentTime / trackDuration : 0
  }

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

public enum RoyaltyTrackingEvent {
  case trackStarted(Song)
  case trackProgress(Song, progress: Double)
  case trackFinished(Song)
}

public enum AudioPlayerEvent {
  case playlistQueued(PlaylistWithSongs)
  case stateChanged(PlaybackState)
  case progressUpdated(PlaybackProgress)
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

  private var batchLoadingTask: Task<Void, Never>?

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
      eventSubject.send(.volumeChanged(newValue))
    }
  }

  // MARK: - Events Publisher

  private let eventSubject = PassthroughSubject<AudioPlayerEvent, Never>()
  public var events: AnyPublisher<AudioPlayerEvent, Never> {
    eventSubject.eraseToAnyPublisher()
  }

  private let royaltyEventSubject = PassthroughSubject<RoyaltyTrackingEvent, Never>()
  public var royaltyEvents: AnyPublisher<RoyaltyTrackingEvent, Never> {
    royaltyEventSubject.eraseToAnyPublisher()
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
    log.info("Starting play for playlist: \(playlistWithSongs.playlist.name) with \(playlistWithSongs.songs.count) songs")

    guard !playlistWithSongs.songs.isEmpty else {
      state = .stopped
      eventSubject.send(.errorOccurred(AudioError.emptyPlaylist))
      return
    }

    currentPlaylist = playlistWithSongs
    let p = playlistWithSongs
    await setupPlayer(with: p)
  }

  @MainActor
  public func resume() {
    guard case .paused(let song, let index) = state else {
      return
    }
    player?.play()
    state = .playing(song, index: index)
    eventSubject.send(.stateChanged(state))
  }

  @MainActor
  public func pause() {
    guard case .playing(let song, let index) = state else {
      return
    }
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
  }

  public func setRepeatMode(_ mode: RepeatMode) {
    repeatMode = mode
  }

  @MainActor
  private func queueSongs(_ songs: [Song]) async {
    batchLoadingTask?.cancel()
    batchLoadingTask = nil

    guard !songs.isEmpty else {
      return
    }

    let initialSize = 1

    guard let firstSong = songs.first else {
      return
    }

    let urlString = firstSong.audio.mp3.url
    guard let itemUrl = URL(string: urlString) else {
      log.info("Invalid URL for first song: \(urlString)")
      return
    }

    let itemAsset = AVURLAsset(url: itemUrl)
    let loadedAsset = await withCheckedContinuation { continuation in
      itemAsset.loadValuesAsynchronously(forKeys: [
        "playable", "duration", "tracks",
      ]) {
        continuation.resume(returning: itemAsset)
      }
    }

    let item = AVPlayerItem(asset: loadedAsset)

    playerItems = [item]

    guard let player = player else {
      log.info("Player is nil, cannot start playback")
      return
    }

    player.removeAllItems()
    player.replaceCurrentItem(with: item)
    player.play()


    batchLoadingTask = Task {
      guard songs.count > initialSize else {
        return
      }

      let remainingSongs: [Song] = Array(songs[initialSize...])
      let batchSize = 30

      for batchIndex in stride(from: 0, to: remainingSongs.count, by: batchSize)
      {
        guard !Task.isCancelled else {
          return
        }
        let endIndex = min(batchIndex + batchSize, remainingSongs.count)
        let batch = Array(remainingSongs[batchIndex..<endIndex])

        let batchItems: [AVPlayerItem] = await Task {
          await Task.yield()
          let assets = await songsToAssets(batch)
          await Task.yield()
          let playableAssets = await makeAssetsPlayable(assets)
          await Task.yield()
          return assetsToItems(playableAssets)
        }.value

        guard !batchItems.isEmpty else {
          continue
        }

        guard !Task.isCancelled else {
          return
        }

        playerItems.append(contentsOf: batchItems)

        for (_, item) in batchItems.enumerated() {
          player.insert(item, after: nil)
        }
      }
    }
  }

  @MainActor
  private func setupPlayer(with playlistWithSongs: PlaylistWithSongs) async {
    batchLoadingTask?.cancel()
    batchLoadingTask = nil

    guard !playlistWithSongs.songs.isEmpty else {
      state = .idle
      eventSubject.send(.errorOccurred(AudioError.emptyPlaylist))
      return
    }

    if player == nil {
      player = AVQueuePlayer()
      player?.automaticallyWaitsToMinimizeStalling = true
      player?.volume = volume
      setupObservers()
    }

    if let firstSong = playlistWithSongs.songs.first {
      currentSong = firstSong
      state = .playing(firstSong, index: 0)
      currentSongIndex = 0
      eventSubject.send(.playlistQueued(playlistWithSongs))
      eventSubject.send(.stateChanged(state))
    }

    await queueSongs(playlistWithSongs.songs)
    updateProgressFromPlayer()
  }

  @MainActor
  private func setupObservers() {
    guard let player = player else {
      return
    }

    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
      .receive(on: DispatchQueue.main)
      .compactMap { $0.object as? AVPlayerItem }
      .sink { [weak self] item in
        self?.handleItemDidPlayToEnd(item)
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled)
      .receive(on: DispatchQueue.main)
      .compactMap { $0.object as? AVPlayerItem }
      .sink { [weak self] item in
        self?.handlePlaybackStalled(item)
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(
      for: .AVPlayerItemFailedToPlayToEndTime
    )
    .receive(on: DispatchQueue.main)
    .compactMap { $0.object as? AVPlayerItem }
    .sink { [weak self] item in
      self?.handlePlaybackFailed(item)
    }
    .store(in: &cancellables)

    player.publisher(for: \.currentItem)
      .receive(on: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] item in
        self?.handleCurrentItemChanged(item)
      }
      .store(in: &cancellables)

    player.publisher(for: \.timeControlStatus)
      .receive(on: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] status in
        self?.handleTimeControlStatusChanged(status)
      }
      .store(in: &cancellables)

    let interval = CMTime(seconds: 1, preferredTimescale: 1)
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
      log.info("Playback failed: \(error)")
      eventSubject.send(.songNetworkFailure(error))
      pause()
    }
  }

  @MainActor
  private func handleItemDidPlayToEnd(_ item: AVPlayerItem) {
    guard let playlist = currentPlaylist,
      let itemIndex = playerItems.firstIndex(of: item),
      itemIndex < playlist.songs.count
    else {
      return
    }

    let song = playlist.songs[itemIndex]
    royaltyEventSubject.send(.trackFinished(song))

    let isLastSong = itemIndex == playlist.songs.count - 1

    switch repeatMode {
    case .none:
      if isLastSong {
        eventSubject.send(.playlistCompleted)
        stop()
      }

    case .all:
      if isLastSong {
        eventSubject.send(.playlistCompleted)
        Task {
          await replayAllSongs()
        }
      }
    }
  }

  @MainActor
  private func handleCurrentItemChanged(_ item: AVPlayerItem?) {
    guard let item = item else {
      currentSong = nil
      return
    }

    guard let playlist = currentPlaylist,
      let itemIndex = playerItems.firstIndex(of: item),
      itemIndex < playlist.songs.count
    else {
      return
    }

    let song = playlist.songs[itemIndex]

    currentSong = song
    currentSongIndex = itemIndex

    royaltyEventSubject.send(.trackStarted(song))

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
    guard let song = currentSong else {
      return
    }

    let newState: PlaybackState
    switch status {
    case .playing:
      newState = .playing(song, index: currentSongIndex)
    case .paused:
      newState = .paused(song, index: currentSongIndex)
    case .waitingToPlayAtSpecifiedRate:
      newState = state
    @unknown default:
      newState = state
    }

    if newState != state {
      state = newState
      eventSubject.send(.stateChanged(newState))
    }
  }

  @MainActor
  private func updateProgressFromPlayer() {
    guard let currentItem = player?.currentItem else {
      return
    }

    guard let playlist = currentPlaylist else {
      return
    }

    guard let index = playerItems.firstIndex(of: currentItem) else {
      return
    }

    let trackCurrentTime = currentItem.currentTime().seconds.rounded(.down)
    let trackDuration = currentItem.duration

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

      if let song = currentSong {
        let progressValue = trackDuration.seconds > 0 ? trackCurrentTime / trackDuration.seconds : 0.0
        royaltyEventSubject.send(.trackProgress(song, progress: progressValue))
      }
    }
  }

  private func clearQueue() {
    player?.removeAllItems()
    playerItems.removeAll()
  }

  @MainActor
  private func replayAllSongs() async {
    batchLoadingTask?.cancel()
    batchLoadingTask = nil

    guard let playlist = currentPlaylist else {
      return
    }

    if playerItems.count == playlist.songs.count {
      player?.removeAllItems()
      for item in playerItems {
        player?.insert(item, after: nil)
      }
    } else {
      await queueSongs(playlist.songs)
    }

    currentSongIndex = 0
    if let firstSong = playlist.songs.first {
      currentSong = firstSong
      state = .playing(firstSong, index: 0)
      eventSubject.send(.stateChanged(state))
    }
  }

  private func destroyPlayer() {
    batchLoadingTask?.cancel()
    batchLoadingTask = nil
    cancellables.removeAll()

    if let observer = progressObserver {
      player?.removeTimeObserver(observer)
      progressObserver = nil
    }

    if let player = player {
      Task { @MainActor in
        player.pause()
      }
    }

    player = nil
    playerItems.removeAll()
  }
}
