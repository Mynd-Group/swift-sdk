import AVFoundation
import Combine
import MediaPlayer

private let log = Logger(prefix: "AudioPlayerService")
public final class AudioPlayerService: AudioPlayer, ObservableObject {
    // MARK: - Published State

    @Published public private(set) var state: PlayerState
    @Published public private(set) var isPlaying: Bool = false

    // MARK: - Events

    private let eventsSubject = PassthroughSubject<PlayerEvent, Never>()
    public var events: AnyPublisher<PlayerEvent, Never> {
        eventsSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private var player: AVQueuePlayer?
    private var playerItems: [AVPlayerItem] = []
    private var currentPlaylist: PlaylistWithSongs?
    private var progressObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var itemToIndexMap: [AVPlayerItem: Int] = [:]

    // MARK: - Initialization

    public init() {
        state = PlayerState(
            status: .stopped,
            currentTime: 0,
            totalTime: 0,
            currentTrackIndex: 0,
            totalTracks: 0,
            repeatMode: .none,
        )

        configureAudioSession()
        setupNotifications()
    }

    // MARK: - Public Methods

    public func play(playlist: PlaylistWithSongs) async {
        guard !playlist.songs.isEmpty else {
            log.info("AudioPlayerService: Cannot play empty playlist")
            eventsSubject.send(.errorOccurred(AudioPlayerError.emptyPlaylist))
            return
        }

        // Do heavy work off main thread
        let items: [AVPlayerItem] = playlist.songs.compactMap { song in
            guard let url = URL(string: song.audio.mp3.url) else {
                log.info("AudioPlayerService: Invalid URL for song: \(song.name)")
                return nil
            }
            let asset = AVAsset(url: url)
            return AVPlayerItem(asset: asset)
        }

        guard !items.isEmpty else {
            log.info("AudioPlayerService: No valid audio URLs found")
            await MainActor.run {
                eventsSubject.send(.errorOccurred(AudioPlayerError.invalidAudioURL))
            }
            return
        }

        // Set up index mapping off main thread
        var indexMap: [AVPlayerItem: Int] = [:]
        for (index, item) in items.enumerated() {
            indexMap[item] = index
        }

        // Now do the main thread work quickly
        cleanupPlayer()
        currentPlaylist = playlist
        playerItems = items
        itemToIndexMap = indexMap

        player = AVQueuePlayer(items: playerItems)
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.allowsExternalPlayback = true

        setupPlayerObservers()
        setupProgressObserver()
        setupRemoteCommandCenter()

        updateState(status: .playing)
        player?.play()
    }

    public func resume() {
        guard let player = player else {
            log.info("AudioPlayerService: Cannot resume - no player available")
            return
        }

        // This is needed to correctly recover from interuptions
        // i hope - testing
        #if os(iOS)
            // Ensure audio session is active
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                log.error("Failed to activate audio session in resume: \(error)")
                eventsSubject.send(.errorOccurred(error))
                return
            }
        #endif

        player.play()
        isPlaying = true
        updateState(status: .playing)
    }

    public func pause() {
        guard let player = player else {
            log.info("AudioPlayerService: Cannot pause - no player available")
            return
        }
        player.pause()
        isPlaying = false
        updateState(status: .paused)
    }

    public func setRepeatMode(_ mode: RepeatMode) {
        updateState(repeatMode: mode)
    }

    public func stop() {
        cleanupPlayer()
        isPlaying = false
        updateState(status: .stopped)
    }

    // MARK: - Private Setup

    private func configureAudioSession() {
        #if os(iOS)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(
                    .playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
                try session.setActive(true)
                log.info("AudioPlayerService: Audio session configured for background playback")
            } catch {
                log.info("AudioPlayerService: Failed to configure audio session: \(error)")
                eventsSubject.send(.errorOccurred(error))
            }
        #endif
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let item = notification.object as? AVPlayerItem {
                    self?.handleItemDidPlayToEnd(item)
                }
            }
            .store(in: &cancellables)

        #if os(iOS)
            NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    self?.handleInterruption(notification)
                }
                .store(in: &cancellables)
        #endif
    }

    private func setupPlayerObservers() {
        guard let player = player else { return }

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .playing:
                    self?.isPlaying = true
                    self?.updateState(status: .playing)
                    self?.eventsSubject.send(.bufferingStateChanged(isBuffering: false))
                case .paused:
                    self?.isPlaying = false
                    self?.updateState(status: .paused)
                case .waitingToPlayAtSpecifiedRate:
                    self?.eventsSubject.send(.bufferingStateChanged(isBuffering: true))
                    self?.updateState(status: .buffering)
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)

        player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.handleCurrentItemChanged(item)
            }
            .store(in: &cancellables)

        for item in playerItems {
            item.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    if status == .failed, let error = item.error {
                        log.info("AudioPlayerService: Player item failed: \(error)")
                        self?.eventsSubject.send(.errorOccurred(error))
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func setupProgressObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        progressObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }

    // MARK: - Remote Commands

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false

        updateNowPlayingInfo()
    }

    // MARK: - Event Handlers

    private func handleCurrentItemChanged(_ item: AVPlayerItem?) {
        guard let item = item,
            let index = itemToIndexMap[item]
        else { return }

        eventsSubject.send(.trackStarted(index: index))
        updateProgress()
        updateNowPlayingInfo()
    }

    private func handleItemDidPlayToEnd(_ item: AVPlayerItem) {
        guard let index = itemToIndexMap[item] else { return }

        eventsSubject.send(.trackCompleted(index: index))

        switch state.repeatMode {
        case .none:
            if player?.items().isEmpty == true {
                eventsSubject.send(.playlistCompleted)
                updateState(status: .stopped)
            }

        case .one:
            item.seek(to: .zero) { [weak self] _ in
                Task { @MainActor in
                    self?.player?.play()
                }
            }

        case .all:
            if player?.items().isEmpty == true {
                eventsSubject.send(.playlistCompleted)
                if let playlist = currentPlaylist {
                    Task {
                        await self.play(playlist: playlist)
                    }
                }
            }
        }
    }

    #if os(iOS)
        @MainActor
        private func handleInterruption(_ notification: Notification) {
            log
                .info(
                    "AudioPlayerService: handleInterruption",
                    dictionary: ["notification": notification]
                )
            guard let userInfo = notification.userInfo,
                let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else {
                log.info("AudioPlayerService: Invalid interruption notification")
                return
            }

            switch type {
            case .began:
                log.info("AudioPlayerService: Interruption began, pausing playback")
                pause()
            case .ended:
                log.info("AudioPlayerService: Interruption ended")
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        log.info("AudioPlayerService: Resuming playback after interruption")
                        resume()
                    } else {
                        log.info("AudioPlayerService: Interruption ended but should not resume")
                    }
                }
            @unknown default:
                log.info("AudioPlayerService: Unknown interruption type")
                break
            }
        }
    #endif

    // MARK: - State Updates

    private func updateState(
        status: PlayerState.PlaybackStatus? = nil,
        repeatMode: RepeatMode? = nil
    ) {
        let currentIndex = getCurrentTrackIndex()
        let progress = calculateProgress()

        state = PlayerState(
            status: status ?? state.status,
            currentTime: progress.current,
            totalTime: progress.total,
            currentTrackIndex: currentIndex,
            totalTracks: playerItems.count,
            repeatMode: repeatMode ?? state.repeatMode
        )
    }

    private func updateProgress() {
        let progress = calculateProgress()
        let currentIndex = getCurrentTrackIndex()

        if abs(state.currentTime - progress.current) > 0.05
            || state.currentTrackIndex != currentIndex
        {
            updateState()
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let playlist = currentPlaylist else { return }

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = playlist.playlist.name
        info[MPMediaItemPropertyArtist] = "MyndStream"
        info[MPMediaItemPropertyPlaybackDuration] = state.totalTime
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = state.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Helper Methods

    private func calculateProgress() -> (current: TimeInterval, total: TimeInterval) {
        guard let player = player,
            let currentItem = player.currentItem
        else {
            return (0, 0)
        }

        var totalTime: TimeInterval = 0
        var currentTime: TimeInterval = 0
        let currentIndex = getCurrentTrackIndex()

        // REFACTOR: the base of this could be done once on item change
        // we don't need to calculate the duration up to now each time
        for item in playerItems {
            let duration = item.asset.duration.seconds
            if !duration.isNaN && !duration.isInfinite {
                totalTime += duration
            }
        }

        for (index, item) in playerItems.enumerated() {
            if index < currentIndex {
                let duration = item.asset.duration.seconds
                if !duration.isNaN && !duration.isInfinite {
                    currentTime += duration
                }
            } else if index == currentIndex {
                let itemTime = currentItem.currentTime().seconds
                if !itemTime.isNaN {
                    currentTime += itemTime
                }
                break
            }
        }

        return (currentTime, totalTime)
    }

    private func getCurrentTrackIndex() -> Int {
        guard let currentItem = player?.currentItem,
            let index = itemToIndexMap[currentItem]
        else {
            return 0
        }
        return index
    }

    private func cleanupPlayer() {
        if let observer = progressObserver {
            player?.removeTimeObserver(observer)
            progressObserver = nil
        }

        player?.pause()
        player = nil
        playerItems.removeAll()
        itemToIndexMap.removeAll()
        cancellables.removeAll()

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
