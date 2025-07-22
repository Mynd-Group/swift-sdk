import AVFoundation
import Combine
import MediaPlayer

private let log = Logger(prefix: "AudioPlayerService")
/// A platform-agnostic façade for an audio-playback engine.
@MainActor
public protocol AudioClientProtocol: AnyObject {

    // MARK: Read-only state / observability
    var events:   AnyPublisher<AudioPlayerEvent, Never> { get }
    var state:    PlaybackState        { get }
    var progress: PlaybackProgress     { get }
    
    /// Convenience flag
    var isPlaying: Bool { get }
    
    /// Current context (optional helpers)
    var currentSong:     Song?              { get }
    var currentPlaylist: PlaylistWithSongs? { get }

    // MARK: Playback control
    func play(_ playlist: PlaylistWithSongs) async
    func pause()
    func resume()
    func stop() async
    
    func setRepeatMode(_ mode: RepeatMode)
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
        
        public init() {}
    }
    
    // MARK: -- Public surface
    public var events: AnyPublisher<AudioPlayerEvent, Never> { core.events }
    public var state: PlaybackState { core.state }
    public var progress: PlaybackProgress { core.progress }
    
    // MARK: -- Private
    private let core = CoreAudioPlayer()
    
    private var interruptionHandler = InterruptionHandler()
    private var sessionHandler = AudioSessionHandler()
    private var nowPlayingHandler = NowPlayingInfoCenterHandler()
    
    private var cancellables = Set<AnyCancellable>()
    private let cfg: Configuration
    
    // MARK: -- Init
    public init(configuration: Configuration = .init()) {
        cfg = configuration
        setupAuxiliaryPipelines()
    }
    
    // MARK: -- Public player controls ----------------------------------------------------------
    public func play(_ playlist: PlaylistWithSongs) async {
        _ = try? activateSessionIfNeeded()
        await core.play(playlist)
    }
    
    public func pause() { core.pause() }
  
    public func resume() { core.resume() }
  
    public func stop() async {
        await core.stop()
        deactivateSessionIfNeeded()
    }
  
    public func setRepeatMode(_ mode: RepeatMode) { core.setRepeatMode(mode) }
    
    // MARK: -- Helpers -------------------------------------------------------------------------
    private func setupAuxiliaryPipelines() {
  #if os(iOS)
      if cfg.handleInterruptions {
        func callback(_ note: Notification) {
            guard
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }                    // malformed notification – bail out

            switch type {
              case .began:
                core.pause()                   // your player pauses

              case .ended:
                core.resume()

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
      #endif
    }
    
    private func updateNowPlayingInfo(for state: PlaybackState) {
        guard case .playing(_, _) = state else { return }
        
        let info = InfoUpdate(
            titleName: core.currentPlaylist?.playlist.name ?? "Unknown",
            artistName: "MyndGroup",
            duration: core.progress.playlistDuration,
            currentTime: core.progress.playlistCurrentTime,
            rate: 1.0
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
