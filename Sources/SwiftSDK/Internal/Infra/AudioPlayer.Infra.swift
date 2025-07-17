import AVFoundation

private extension Song {
    func toAVPlayerItem() async -> AVPlayerItem {
        let url = URL(string: audio.hls.url)!
        return await AVPlayerItem(asset: AVAsset(url: url))
    }
}

private extension PlaylistWithSongs {
    func toAVPlayerItems() async -> [AVPlayerItem] {
        return await withTaskGroup(of: AVPlayerItem.self) { group in
            for song in songs {
                group.addTask {
                    await song.toAVPlayerItem()
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
    }
}

let logger = Logger(prefix: "AudioPlayer")
@MainActor
class AudioPlayerInfraService: AudioPlayerProtocol {
    private var playlist: PlaylistWithSongs?
    private var player: AVQueuePlayer?
    private var playerItems: [AVPlayerItem]?
    private var currentItemIndex: Int = 0
    private var repeatMode: RepeatMode = .none

    init() {
        playlist = nil
        player = nil
        playerItems = nil
    }

    func startPlaylist(playlistWithSongs: PlaylistWithSongs) async {
        logger.info("Starting playlist", dictionary: ["playlistId": playlistWithSongs.playlist, "songsCount": playlistWithSongs.songs.count])
        guard !playlistWithSongs.songs.isEmpty else {
            logger.warn("Cannot start an empty playlist", dictionary: ["playlistId": playlistWithSongs.playlist, "songsCount": playlistWithSongs.songs.count])
            return
        }

        logger.debug("Converting songs to AVPlayerItems")
        let items = await playlistWithSongs.toAVPlayerItems()
        setPlayerWithNewItems(items: items)
    }

    func play() {
        guard let player = player else {
            logger.error("Cannot play, player is nil")
            return
        }
        logger.info("Playing current item", dictionary: ["currentItemIndex": currentItemIndex])
        player.play()
    }

    func pause() {
        guard let player = player else {
            logger.error("Cannot pause, player is nil")
            return
        }

        logger.info("Pausing current item", dictionary: ["currentItemIndex": currentItemIndex])

        player.pause()
    }

    func destroy() {
        player?.pause()
        player = nil
        playerItems = nil
        currentItemIndex = 0
        logger.info("Player destroyed")
    }

    func setRepeatMode(_ mode: RepeatMode) {
        logger.info("Setting repeat mode", dictionary: ["mode": repeatMode])
        repeatMode = mode
    }

    private func setupLooping() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor in
                self?.handleItemEnd(item!)
            }
        }
    }

    private func handleItemEnd(_ item: AVPlayerItem) {
        guard item == player?.currentItem else { return }

        switch repeatMode {
        case .loopSong:
            // Restart current song
            item.seek(to: .zero) { [weak self] _ in
                Task {
                    await self?.player?.play()
                }
            }

        case .loopPlaylist:
            // Check if we're at the end of the queue
            if player?.items().isEmpty == true {
                setPlayerWithNewItems(items: playerItems!)
            }
        // Otherwise, AVQueuePlayer will advance automatically

        case .none:
            // Let it naturally end or advance
            break
        }
    }

    private func setPlayerWithNewItems(items: [AVPlayerItem]) {
        logger.info("Resetting player with new items", dictionary: ["itemsCount": items.count])
        player?.pause()
        player = AVQueuePlayer(items: items)
        currentItemIndex = 0
        player!.play()
    }
}
