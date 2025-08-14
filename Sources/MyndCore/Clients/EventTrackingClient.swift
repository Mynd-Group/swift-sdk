import Foundation

protocol EventTrackingClientProtocol: Sendable {
  func trackEvent(_ event: EventTrackingEvent) async throws
}

public enum EventTrackingEvent: Sendable {
  case trackStarted(
    song: Song, playlist: Playlist, songSessionId: String, sessionId: String,
    playlistSessionId: String)
  case trackProgress(
    song: Song, playlist: Playlist, progress: Double, songSessionId: String, sessionId: String,
    playlistSessionId: String)
  case trackCompleted(
    song: Song, playlist: Playlist, songSessionId: String, sessionId: String,
    playlistSessionId: String)
  case playlistStarted(playlist: PlaylistWithSongs, sessionId: String, playlistSessionId: String)
  case playlistCompleted(playlist: PlaylistWithSongs, sessionId: String, playlistSessionId: String)
}

struct EventTrackingClientInfraConfig {
  public let authedHttpClient: HttpClientProtocol
}

private let log = Logger(prefix: "EventTrackingClient.Infra")
actor EventTrackingClientInfraService: EventTrackingClientProtocol {
  private var sentProgressEvents: [String: Double] = [:]
  private let thresholds: [Double] = [0.25, 0.5, 0.75]
  private let authedHttpClient: HttpClientProtocol

  init(config: EventTrackingClientInfraConfig) {
    self.authedHttpClient = config.authedHttpClient
  }

  func getProgressId(for songId: String, sessionId: String, playlistSessionId: String) -> String {
    return "\(songId)-\(sessionId)-\(playlistSessionId)"
  }

  private func getNextProgressThreshold(
    for songId: String, sessionId: String, playlistSessionId: String
  ) -> Double? {
    let lastSentProgress =
      sentProgressEvents[
        getProgressId(for: songId, sessionId: sessionId, playlistSessionId: playlistSessionId)] ?? 0
    return thresholds.first(where: { $0 > lastSentProgress })
  }

  private func getValidThreshold(
    for songId: String, sessionId: String, playlistSessionId: String, progress: Double
  ) -> Double? {
    if progress.isNaN || progress < 0 || progress > 1 {
      log.info("Skipping progress event: invalid progress", dictionary: ["progress": progress])
      return nil
    }
    guard
      let nextThreshold = getNextProgressThreshold(
        for: songId, sessionId: sessionId, playlistSessionId: playlistSessionId)
    else {
      return nil
    }
    if progress < nextThreshold { return nil }
    log.info(
      "Sending progress event", dictionary: ["progress": progress, "nextThreshold": nextThreshold])
    return nextThreshold
  }

  private let progressLock = NSLock()

  public func trackEvent(_ event: EventTrackingEvent) async throws {
    do {
      let payload = buildPayload(from: event)
      guard let payload = payload else {
        return
      }
      guard let url = URL(string: "\(Config.baseUrl)/integration-events/") else {
        log.error("Failed to create events URL")
        throw URLError(.badURL)
      }
      log.info("Sending event", dictionary: ["sessionId": payload.sessionId])
      if case .trackProgress(let song, _, let progress, _, let sessionId, let playlistSessionId) =
        event
      {
        progressLock.withLock {
          if let threshold = getValidThreshold(
            for: song.id, sessionId: sessionId, playlistSessionId: playlistSessionId,
            progress: progress)
          {
            let key = getProgressId(
              for: song.id, sessionId: sessionId, playlistSessionId: playlistSessionId)
            sentProgressEvents[key] = threshold
          }

        }
      }
      let _: EmptyResponse = try await authedHttpClient.post(url, body: payload, headers: nil)
      log.info("Event sent successfully", dictionary: ["sessionId": payload.sessionId])
    } catch {
      log.error("Failed to send event: \(error)")
      throw error
    }
  }

  private func buildPayload(from event: EventTrackingEvent) -> (any TrackingEventPayload)? {
    switch event {
    case .trackStarted(
      let song, let playlist, let songSessionId, let sessionId, let playlistSessionId):
      return TrackStartedPayload(
        songId: song.id,
        songName: song.name,
        songDuration: song.audio.mp3.durationInSeconds,
        playlistId: playlist.id,
        playlistName: playlist.name,
        songSessionId: songSessionId,
        sessionId: sessionId,
        playlistSessionId: playlistSessionId
      )

    case .trackProgress(
      let song, let playlist, let progress, let songSessionId, let sessionId, let playlistSessionId):
      guard
        let validThreshold = getValidThreshold(
          for: song.id, sessionId: sessionId, playlistSessionId: playlistSessionId,
          progress: progress
        )
      else {
        return nil
      }
      return TrackProgressPayload(
        songId: song.id,
        songName: song.name,
        songDuration: song.audio.mp3.durationInSeconds,
        playlistId: playlist.id,
        playlistName: playlist.name,
        songSessionId: songSessionId,
        progress: validThreshold,
        sessionId: sessionId,
        playlistSessionId: playlistSessionId
      )

    case .trackCompleted(
      let song, let playlist, let songSessionId, let sessionId, let playlistSessionId):
      return TrackCompletedPayload(
        songId: song.id,
        songName: song.name,
        songDuration: song.audio.mp3.durationInSeconds,
        playlistId: playlist.id,
        playlistName: playlist.name,
        songSessionId: songSessionId,
        sessionId: sessionId,
        playlistSessionId: playlistSessionId
      )

    case .playlistStarted(let playlistWithSongs, let sessionId, let playlistSessionId):
      let playlist = playlistWithSongs.playlist
      let playlistDuration = playlistWithSongs.songs.reduce(0) {
        $0 + $1.audio.mp3.durationInSeconds
      }
      return PlaylistStartedPayload(
        playlistId: playlist.id,
        playlistName: playlist.name,
        playlistGenre: playlist.genre ?? "",
        playlistBPM: playlist.bpm ?? 0,
        playlistInstrumentation: playlist.instrumentation ?? "",
        playlistDuration: playlistDuration,
        sessionId: sessionId,
        playlistSessionId: playlistSessionId
      )

    case .playlistCompleted(let playlistWithSongs, let sessionId, let playlistSessionId):
      let playlist = playlistWithSongs.playlist
      let playlistDuration = playlistWithSongs.songs.reduce(0) {
        $0 + $1.audio.mp3.durationInSeconds
      }
      return PlaylistCompletedPayload(
        playlistId: playlist.id,
        playlistName: playlist.name,
        playlistGenre: playlist.genre ?? "",
        playlistBPM: playlist.bpm ?? 0,
        playlistInstrumentation: playlist.instrumentation ?? "",
        playlistDuration: playlistDuration,
        sessionId: sessionId,
        playlistSessionId: playlistSessionId
      )
    }
  }
}

protocol TrackingEventPayload: Encodable, Sendable {
  var sessionId: String { get }
  var playlistSessionId: String { get }
  var timestamp: Int { get }
  var idempotencyKey: String { get }
}

protocol TrackEventPayload: TrackingEventPayload {
  var type: String { get }
  var songId: String { get }
  var songName: String { get }
  var songDuration: Int { get }
  var playlistId: String { get }
  var playlistName: String { get }
  var songSessionId: String { get }
}

protocol PlaylistEventPayload: TrackingEventPayload {
  var type: String { get }
  var playlistId: String { get }
  var playlistName: String { get }
  var playlistGenre: String { get }
  var playlistBPM: Int { get }
  var playlistInstrumentation: String { get }
  var playlistDuration: Int { get }
}

struct TrackStartedPayload: TrackEventPayload {
  let type: String = "track:started"
  let songId: String
  let songName: String
  let songDuration: Int
  let playlistId: String
  let playlistName: String
  let songSessionId: String
  let sessionId: String
  let playlistSessionId: String
  let timestamp: Int = currentUnixTimeMs()
  let idempotencyKey: String = id()
}

struct TrackProgressPayload: TrackEventPayload {
  let type: String = "track:progress"
  let songId: String
  let songName: String
  let songDuration: Int
  let playlistId: String
  let playlistName: String
  let songSessionId: String
  let progress: Double
  let sessionId: String
  let playlistSessionId: String
  let timestamp: Int = currentUnixTimeMs()
  let idempotencyKey: String = id()
}

struct TrackCompletedPayload: TrackEventPayload {
  let type: String = "track:completed"
  let songId: String
  let songName: String
  let songDuration: Int
  let playlistId: String
  let playlistName: String
  let songSessionId: String
  let sessionId: String
  let playlistSessionId: String
  let timestamp: Int = currentUnixTimeMs()
  let idempotencyKey: String = id()
}

struct PlaylistStartedPayload: PlaylistEventPayload {
  let type: String = "playlist:started"
  let playlistId: String
  let playlistName: String
  let playlistGenre: String
  let playlistBPM: Int
  let playlistInstrumentation: String
  let playlistDuration: Int
  let sessionId: String
  let playlistSessionId: String
  let timestamp: Int = currentUnixTimeMs()
  let idempotencyKey: String = id()
}

struct PlaylistCompletedPayload: PlaylistEventPayload {
  let type: String = "playlist:completed"
  let playlistId: String
  let playlistName: String
  let playlistGenre: String
  let playlistBPM: Int
  let playlistInstrumentation: String
  let playlistDuration: Int
  let sessionId: String
  let playlistSessionId: String
  let timestamp: Int = currentUnixTimeMs()
  let idempotencyKey: String = id()
}

private struct EmptyResponse: Decodable {}

enum EventTrackingError: Error {
  case invalidSessionId
  case invalidProgress
  case invalidId
}
