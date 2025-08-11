import AVFoundation
import Combine
import MediaPlayer

private let log = Logger(prefix: "AudioPlayerService")
/// A platform-agnostic façade for an audio-playback engine.
@MainActor
public protocol AudioClientProtocol: AnyObject {

  // MARK: Read-only state / observability
  var events: AnyPublisher<AudioPlayerEvent, Never> { get }
  var royaltyEvents: AnyPublisher<RoyaltyTrackingEvent, Never> { get }
  var state: PlaybackState { get }
  var progress: PlaybackProgress { get }

  /// Convenience flag
  var isPlaying: Bool { get }

  /// Current context (optional helpers)
  var currentSong: Song? { get }
  var currentPlaylist: PlaylistWithSongs? { get }

  // MARK: Playback control
  func play(_ playlist: PlaylistWithSongs) async
  func pause()
  func resume()
  func stop() async

  func setRepeatMode(_ mode: RepeatMode)

  // Volume control
  var volume: Float { get }
  func setVolume(_ value: Float)
}

@MainActor
public final class AudioClient: AudioClientProtocol {
  public var isPlaying: Bool {
    if case .playing = state { return true }
    return false
  }

  public var currentSong: Song? {
    if core.currentSong == nil { return nil }
    return core.currentSong
  }

  public var currentPlaylist: PlaylistWithSongs? {
    if core.currentPlaylist == nil { return nil }
    return core.currentPlaylist

  }

  // MARK: -- Opt-in flags
  public struct Configuration: Sendable {
    public var handleInterruptions: Bool = true
    public var handleInfoItemUpdates: Bool = true
    public var handleAudioSession: Bool = true
    public var handleCommandCenter: Bool = true

    public init() {}
  }

  // MARK: -- Public surface
  public var events: AnyPublisher<AudioPlayerEvent, Never> { core.events }
  public var royaltyEvents: AnyPublisher<RoyaltyTrackingEvent, Never> { core.royaltyEvents }
  public var state: PlaybackState { core.state }
  public var progress: PlaybackProgress { core.progress }
  public var volume: Float {
    core.volume
  }

  // MARK: -- Private
  private let core = CoreAudioPlayer()

  private var interruptionHandler = InterruptionHandler()
  private var sessionHandler = AudioSessionHandler()
  private var nowPlayingHandler = NowPlayingInfoCenterHandler()
  private var commandCenterHandler = CommandCenterHandler()

  private var cancellables = Set<AnyCancellable>()
  private let cfg: Configuration
  private let listeningSessionManager: ListeningSessionManager
  private let eventTrackingClient: EventTrackingClientInfraService
  private var playlistSessionId: String = id()

  // MARK: -- Init
  init(
    configuration: Configuration, listeningSessionManager: ListeningSessionManager,
    eventTrackingClient: EventTrackingClientInfraService
  ) {
    cfg = configuration
    self.listeningSessionManager = listeningSessionManager
    self.eventTrackingClient = eventTrackingClient

    setupAuxiliaryPipelines()
    setupEventTracking()
  }

  // MARK: -- Public player controls ----------------------------------------------------------
  public func play(_ playlist: PlaylistWithSongs) async {
    playlistSessionId = id()
    _ = try? activateSessionIfNeeded()
    await core.play(playlist)
    let imageUrl = playlist.playlist.image?.url
    let image = imageUrl.flatMap { URL(string: $0) }
    nowPlayingHandler.updateImage(image)
  }

  public func pause() { core.pause() }

  public func resume() { core.resume() }

  public func stop() async {
    core.stop()
    deactivateSessionIfNeeded()
  }

  public func setRepeatMode(_ mode: RepeatMode) { core.setRepeatMode(mode) }

  public func setVolume(_ value: Float) {
    core.setVolume(value)
  }

  private func setupEventTracking() {
    core.events
      .sink { [weak self] event in
        guard let self else { return }
        switch event {
        case .playlistQueued(let playlist):
          self.playlistSessionId = id()
          do {
            Task {
              try await eventTrackingClient.trackEvent(
                .playlistStarted(
                  playlist: playlist.playlist,
                  sessionId: self.listeningSessionManager.getSessionId(),
                  playlistSessionId: self.playlistSessionId))
            }
          } catch {
            log.error("Failed to track event: \(error)")
          }
        case .playlistFinished(let playlist):
          do {
            Task {
              try await eventTrackingClient.trackEvent(
                .playlistCompleted(
                  playlist: playlist.playlist,
                  sessionId: self.listeningSessionManager.getSessionId(),
                  playlistSessionId: self.playlistSessionId))
            }
          } catch {
            log.error("Failed to track event: \(error)")
          }
        default:
          break
        }
      }
      .store(in: &cancellables)

    core.royaltyEvents
      .sink { [weak self] event in
        guard let self else { return }
        switch event {
        case .trackStarted(let song):
          do {
            Task {
              try await eventTrackingClient.trackEvent(
                .trackStarted(
                  song: song, sessionId: self.listeningSessionManager.getSessionId(),
                  playlistSessionId: self.playlistSessionId))
            }
          } catch {
            log.error("Failed to track event: \(error)")
          }

        case .trackProgress(let song, let progress):
          do {
            Task {
              try await eventTrackingClient.trackEvent(
                .trackProgress(
                  song: song, progress: progress,
                  sessionId: self.listeningSessionManager.getSessionId(),
                  playlistSessionId: self.playlistSessionId))
            }
          } catch {
            log.error("Failed to track event: \(error)")
          }

        case .trackFinished(let song):
          do {
            Task {
              try await eventTrackingClient.trackEvent(
                .trackCompleted(
                  song: song, sessionId: self.listeningSessionManager.getSessionId(),
                  playlistSessionId: self.playlistSessionId))
            }
          } catch {
            log.error("Failed to track event: \(error)")
          }
        }
      }
      .store(in: &cancellables)
  }

  // MARK: -- Helpers -------------------------------------------------------------------------
  private func setupAuxiliaryPipelines() {
    #if os(iOS)
      if cfg.handleInterruptions {
        func callback(_ note: Notification) {
          guard
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey]
              as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
          else { return }  // malformed notification – bail out

          switch type {
          case .began:
            core.pause()

          case .ended:
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)

            // Check if we should resume (default to true if no options provided)
            let shouldResume = optionsValue == nil || options.contains(.shouldResume)

            if shouldResume {
              do {
                // Reactivate audio session if needed
                try AVAudioSession.sharedInstance().setActive(true)
                core.resume()
                log.debug("Successfully resumed playback after interruption")
              } catch {
                log.error("Failed to resume playback after interruption: \(error)")
              }
            } else {
              log.debug("Interruption ended but shouldResume is false - not resuming playback")
            }

          @unknown default: break
          }
        }

        interruptionHandler.enable(callback)

      }

      if cfg.handleAudioSession {
        core.events
          .sink { [weak self] event in
            guard let self else { return }
            switch event {
            case .stateChanged(let s):
              self.updateNowPlayingInfo(for: s)
            case .progressUpdated:
              self.updateNowPlayingInfo(for: self.core.state)
            default:
              break
            }
          }
          .store(in: &cancellables)

        nowPlayingHandler.enable()
      }

      if cfg.handleCommandCenter {
        commandCenterHandler.enable(
          onPlay: { [weak self] in
            self?.core.resume()
          },
          onPause: { [weak self] in
            self?.core.pause()
          },
          onTogglePlayPause: { [weak self] in
            guard let self = self else { return }
            if self.core.isPlaying {
              self.core.pause()
            } else {
              self.core.resume()
            }
          }
        )
      }
    #endif
  }

  private func updateNowPlayingInfo(for state: PlaybackState) {
    guard case .playing(_, _) = state else { return }
    guard core.currentPlaylist != nil else { return }

    let info = InfoUpdate(
      titleName: core.currentPlaylist?.playlist.name ?? "Unknown",
      artistName: "Track \(core.currentSongIndex + 1) of \(core.currentPlaylist?.songs.count ?? 0)",
      duration: core.progress.trackDuration,
      currentTime: core.progress.trackCurrentTime,
      rate: 1.0,
    )

    nowPlayingHandler.update(info)
  }

  private func activateSessionIfNeeded() throws -> Bool {
    guard cfg.handleAudioSession else { return false }
    do {
      #if os(iOS)
        try sessionHandler.activate()
      #endif
      return true
    } catch {
      log.error("Failed to activate session: \(error.localizedDescription)")
      return false
    }
  }

  private func deactivateSessionIfNeeded() {
    if cfg.handleAudioSession {
      #if os(iOS)
        sessionHandler.deactivate()
      #endif
    }
  }
}
