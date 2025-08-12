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
    return nextThreshold
  }

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
      log.info("Sending event", dictionary: ["type": payload.type, "sessionId": payload.sessionId])
      if case .trackProgress(let song, let progress, let sessionId, let playlistSessionId) = event {
        if let threshold = getValidThreshold(
          for: song.id, sessionId: sessionId, playlistSessionId: playlistSessionId,
          progress: progress)
        {
          let key = getProgressId(
            for: song.id, sessionId: sessionId, playlistSessionId: playlistSessionId)
          sentProgressEvents[key] = threshold
        }
      }
      let _: EmptyResponse = try await authedHttpClient.post(url, body: payload, headers: nil)
      log.info("Event sent successfully", dictionary: ["type": payload.type])
    } catch {
      log.error("Failed to send event: \(error)")
      throw error
    }
  }

  private func buildPayload(from event: EventTrackingEvent) -> Payload? {
    switch event {
    case .trackStarted(let song, let sessionId, let playlistSessionId):
      return Payload(
        type: "track:started", sessionId: sessionId, songId: song.id, playlistId: nil,
        progress: nil,
        playlistSessionId: playlistSessionId)

    case .trackProgress(let song, let progress, let sessionId, let playlistSessionId):
      guard
        let validThreshold = getValidThreshold(
          for: song.id, sessionId: sessionId, playlistSessionId: playlistSessionId,
          progress: progress
        )
      else {
        return nil
      }
      return Payload(
        type: "track:progress", sessionId: sessionId, songId: song.id, playlistId: nil,
        progress: validThreshold, playlistSessionId: playlistSessionId)

    case .trackCompleted(let song, let sessionId, let playlistSessionId):
      return Payload(
        type: "track:completed", sessionId: sessionId, songId: song.id, playlistId: nil,
        progress: nil, playlistSessionId: playlistSessionId)

    case .playlistStarted(let playlist, let sessionId, let playlistSessionId):
      return Payload(
        type: "playlist:started", sessionId: sessionId, songId: nil, playlistId: playlist.id,
        progress: nil, playlistSessionId: playlistSessionId)

    case .playlistCompleted(let playlist, let sessionId, let playlistSessionId):
      return Payload(
        type: "playlist:completed", sessionId: sessionId, songId: nil, playlistId: playlist.id,
        progress: nil, playlistSessionId: playlistSessionId)
    }
  }
}

private struct Payload: Encodable {
  let idempotencyKey: String = id()
  let type: String
  let sessionId: String
  let songId: String?
  let playlistId: String?
  let progress: Double?
  let playlistSessionId: String
}

private struct EmptyResponse: Decodable {}

enum EventTrackingError: Error {
  case invalidSessionId
  case invalidProgress
  case invalidId
}
