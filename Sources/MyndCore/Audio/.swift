import AVFoundation
import Combine
import Observation

class PlaybackProgressHandler: Equatable {
  
  static public func == (lhs: PlaybackProgressHandler, rhs: PlaybackProgressHandler) -> Bool {
    return lhs === rhs
  }
  
  // Track-level progress
  public var trackCurrentTime: TimeInterval
  public var trackDuration: TimeInterval
  public var trackIndex: Int

  // Playlist-level progress
  public var playlistCurrentTime: TimeInterval
  public var playlistDuration: TimeInterval

  // Computed properties for track
  public var trackProgress: Double {
      trackDuration > 0 ? trackCurrentTime / trackDuration : 0
  }

  // Computed properties for playlist
  public var playlistProgress: Double {
      playlistDuration > 0 ? playlistCurrentTime / playlistDuration : 0
  }
  
  init(songs: [AVPlayerItem], currentIndex: Int){
    _ = trackCurrentTime = 0
    _ = trackDuration = 0
    _ = trackIndex = 0
    
    _ = playlistCurrentTime = 0
    _ = playlistDuration = 0
    
    updateProgress(songs: songs, currentIndex: currentIndex, currentSongProgress: 0)
  }
  
   
  
  public func updateProgress(
    songs: [AVPlayerItem],
    currentIndex: Int,
    currentSongProgress: TimeInterval
  ){
    let previousSongIndex = currentIndex - 1;
    let previousSongs = songs[...previousSongIndex]
    let currentPlaylistProgress = previousSongs.reduce(0) { $0 + $1.duration.seconds }
    
    trackCurrentTime = 0
    trackDuration = songs[currentIndex].duration.seconds
    trackIndex = currentIndex
    
    playlistCurrentTime = currentPlaylistProgress
    playlistDuration = songs.reduce(0) { $0 + $1.duration.seconds }
  }
}
