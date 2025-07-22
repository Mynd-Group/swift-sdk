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
    
    mutating func update(_ update: InfoUpdate) {
        guard isEnabled else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:                update.titleName,
            MPMediaItemPropertyArtist:               update.artistName,
            MPMediaItemPropertyPlaybackDuration:     update.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: update.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate:    update.rate
        ]
    }
}
