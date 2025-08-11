import Foundation

protocol EventTrackingClientProtocol: Sendable {
  func trackEvent(_ event: EventTrackingEvent) async throws
}

public enum EventTrackingEvent: Sendable {
  case trackStarted(song: Song, sessionId: String, playlistSessionId: String)
  case trackProgress(song: Song, progress: Double, sessionId: String, playlistSessionId: String)
  case trackCompleted(song: Song, sessionId: String, playlistSessionId: String)
  case playlistStarted(playlist: Playlist, sessionId: String, playlistSessionId: String)
  case playlistCompleted(playlist: Playlist, sessionId: String, playlistSessionId: String)
}

struct EventTrackingClientInfraConfig {
  public let authedHttpClient: HttpClientProtocol
}

private let log = Logger(prefix: "EventTrackingClient.Infra")
struct EventTrackingClientInfraService: EventTrackingClientProtocol {
  private let authedHttpClient: HttpClientProtocol

  init(config: EventTrackingClientInfraConfig) {
    self.authedHttpClient = config.authedHttpClient
  }

  public func trackEvent(_ event: EventTrackingEvent) async throws {
    do {
      let payload = buildPayload(from: event)
      guard let url = URL(string: "\(Config.baseUrl)/integration/tracking/events") else {
        log.error("Failed to create events URL")
        throw URLError(.badURL)
      }
      log.info("Sending event", dictionary: ["type": payload.type, "sessionId": payload.sessionId])
      //   let _: EmptyResponse = try await authedHttpClient.post(url, body: payload, headers: nil)
      log.info("Event sent successfully", dictionary: ["type": payload.type])
    } catch {
      log.error("Failed to send event: \(error)")
      throw error
    }
  }

  private func buildPayload(from event: EventTrackingEvent) -> Payload {
    switch event {
    case .trackStarted(let song, let sessionId, let playlistSessionId):
      return Payload(
        type: "TrackStarted", sessionId: sessionId, songId: song.id, playlistId: nil, progress: nil,
        playlistSessionId: playlistSessionId)

    case .trackProgress(let song, let progress, let sessionId, let playlistSessionId):
      return Payload(
        type: "TrackProgress", sessionId: sessionId, songId: song.id, playlistId: nil,
        progress: progress, playlistSessionId: playlistSessionId)

    case .trackCompleted(let song, let sessionId, let playlistSessionId):
      return Payload(
        type: "TrackCompleted", sessionId: sessionId, songId: song.id, playlistId: nil,
        progress: nil, playlistSessionId: playlistSessionId)

    case .playlistStarted(let playlist, let sessionId, let playlistSessionId):
      return Payload(
        type: "PlaylistStarted", sessionId: sessionId, songId: nil, playlistId: playlist.id,
        progress: nil, playlistSessionId: playlistSessionId)

    case .playlistCompleted(let playlist, let sessionId, let playlistSessionId):
      return Payload(
        type: "PlaylistCompleted", sessionId: sessionId, songId: nil, playlistId: playlist.id,
        progress: nil, playlistSessionId: playlistSessionId)
    }
  }
}

private struct Payload: Encodable {
  let type: String
  let sessionId: String
  let songId: String?
  let playlistId: String?
  let progress: Double?
  let playlistSessionId: String?
}

private struct EmptyResponse: Decodable {}

enum EventTrackingError: Error {
  case invalidSessionId
  case invalidProgress
  case invalidId
}
