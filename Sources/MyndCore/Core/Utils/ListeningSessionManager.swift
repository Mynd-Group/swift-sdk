import Foundation

func id() -> String {
  UUID().uuidString
}

let activityTimeoutMs = 15 * 60 * 1000

public final class ListeningSessionManager: @unchecked Sendable {
  private var lastActiveAtMs: Int?
  private var currentSessionId: String?
  private let lock = NSLock()

  // Returns the current session id and marks activity (extends the session).
  func getSessionId() -> String {
    lock.lock()
    defer { lock.unlock() }

    if shouldStartNewSession(now: currentUnixTimeMs()) {
      currentSessionId = id()
    }

    lastActiveAtMs = currentUnixTimeMs()
    return currentSessionId!
  }

  // Extends the current session by updating last active time.
  func extendSession() {
    lock.lock()
    defer { lock.unlock() }

    if shouldStartNewSession(now: currentUnixTimeMs()) {
      currentSessionId = id()
    }
    lastActiveAtMs = currentUnixTimeMs()
  }

  // Called only under lock.
  private func shouldStartNewSession(now: Int) -> Bool {
    if lastActiveAtMs == nil { return true }
    if currentSessionId == nil { return true }

    return (now - lastActiveAtMs!) >= activityTimeoutMs
  }
}
