import AVFoundation
import Combine
import MediaPlayer


// MARK: — NowPlayingInfoCenterHandler

struct InfoUpdate {
  public var titleName: String
  public var artistName: String
  public var duration: TimeInterval
  public var currentTime: TimeInterval
  public var rate: Float
}

struct NowPlayingInfoCenterHandler {
    private(set) var isEnabled = false

    mutating func enable()  { isEnabled = true  }
    mutating func disable() { isEnabled = false }

  mutating func updateImage(_ url: URL?) {
      let info = MPNowPlayingInfoCenter.default()
      guard isEnabled else { return }

    guard url != nil else {
          var currentInfo = info.nowPlayingInfo ?? [:]
          currentInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
          info.nowPlayingInfo = currentInfo
          return
      }

     // TODO:
  }

    mutating func update(_ update: InfoUpdate) {
        let info = MPNowPlayingInfoCenter.default()
        guard isEnabled else { return }
        var currentInfo = info.nowPlayingInfo ?? [:]
        currentInfo[MPMediaItemPropertyTitle] = update.titleName
        currentInfo[MPMediaItemPropertyArtist] = update.artistName
        currentInfo[MPMediaItemPropertyPlaybackDuration] = update.duration
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = update.currentTime
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = update.rate
        info.nowPlayingInfo = currentInfo
    }
}
