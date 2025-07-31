# Flutter Bridge Implementation Prompt for MyndStream Swift SDK

## Overview
You need to create a Flutter bridge for the MyndStream Swift SDK that provides music streaming capabilities with catalogue browsing and audio playback functionality. The SDK consists of two main components: a **Catalogue Client** for fetching music data and an **Audio Player** for playback control.

## Core SDK Structure

The main SDK class is `MyndSDK` which exposes:
- `catalogue: CatalogueClientProtocol` - For browsing music content
- `player: AudioClientProtocol` - For audio playback control

**Initialization Requirements:**
- Requires an `authFunction: () async throws -> AuthPayloadProtocol` for authentication
- Optional `audioConfiguration: AudioClient.Configuration` for player settings

## Authentication Interface

**AuthPayloadProtocol:**
```dart
class AuthPayload {
  final String accessToken;
  final String refreshToken;
  final int accessTokenExpiresAtUnixMs;
  final bool isExpired;
}
```

## Data Entities

### Category Entity
```dart
class CategoryImage {
  final String id;
  final String url;
}

class Category {
  final String id;
  final String name;
  final CategoryImage? image;
}
```

### Playlist Entity
```dart
class PlaylistImage {
  final String id;
  final String url;
}

class Playlist {
  final String id;
  final String name;
  final PlaylistImage? image;
  final String? description;
  final String? instrumentation;
  final String? genre;
  final int? bpm;
}
```

### Song Entity (Complex Structure)
```dart
class SongImage {
  final String id;
  final String url;
}

class Artist {
  final String id;
  final String name;
}

class SongHLS {
  final String id;
  final String url;
  final int durationInSeconds;
  final String urlExpiresAtISO;
}

class SongMP3 {
  final String id;
  final String url;
  final int durationInSeconds;
  final String urlExpiresAtISO;
}

class Audio {
  final SongHLS hls;
  final SongMP3 mp3;
}

class Song {
  final String id;
  final String name;
  final SongImage? image;
  final Audio audio;
  final List<Artist> artists;
}
```

### Composite Entity
```dart
class PlaylistWithSongs {
  final Playlist playlist;
  final List<Song> songs;
}
```

## Catalogue Client Interface

**Required Methods:**
```dart
abstract class CatalogueClient {
  Future<List<Category>> getCategories();
  Future<Category> getCategory(String categoryId);
  Future<List<Playlist>> getPlaylists(String? categoryId);
  Future<PlaylistWithSongs> getPlaylist(String playlistId);
}
```

**Error Handling:**
- All methods can throw exceptions
- Should handle network errors, authentication failures, and malformed responses
- Include proper logging for debugging

## Audio Player Interface

### Player Configuration
```dart
class AudioConfiguration {
  final bool handleInterruptions;
  final bool handleInfoItemUpdates;
  final bool handleAudioSession;
  final bool handleCommandCenter;
  
  AudioConfiguration({
    this.handleInterruptions = true,
    this.handleInfoItemUpdates = true,
    this.handleAudioSession = true,
    this.handleCommandCenter = true,
  });
}
```

### Playback State & Progress
```dart
enum RepeatMode { none, all }

class PlaybackProgress {
  final double trackCurrentTime;
  final double trackDuration;
  final int trackIndex;
  final double playlistCurrentTime;
  final double playlistDuration;
  
  double get trackProgress => trackDuration > 0 ? trackCurrentTime / trackDuration : 0;
  double get playlistProgress => playlistDuration > 0 ? playlistCurrentTime / playlistDuration : 0;
}

enum PlaybackState {
  idle,
  playing(Song song, int index),
  paused(Song song, int index),
  stopped,
}
```

### Events System
```dart
enum AudioPlayerEvent {
  playlistQueued(PlaylistWithSongs playlist),
  stateChanged(PlaybackState state),
  progressUpdated(PlaybackProgress progress),
  playlistCompleted,
  songNetworkStalled,
  songNetworkFailure(Exception error),
  errorOccurred(Exception error),
  volumeChanged(double volume),
}

enum RoyaltyTrackingEvent {
  trackStarted(Song song),
  trackProgress(Song song, double progress),
  trackFinished(Song song),
}
```

### Audio Player Interface
```dart
abstract class AudioPlayer {
  // State & Observability (Streams)
  Stream<AudioPlayerEvent> get events;
  Stream<RoyaltyTrackingEvent> get royaltyEvents;
  PlaybackState get state;
  PlaybackProgress get progress;
  bool get isPlaying;
  Song? get currentSong;
  PlaylistWithSongs? get currentPlaylist;
  
  // Playback Control
  Future<void> play(PlaylistWithSongs playlist);
  void pause();
  void resume();
  Future<void> stop();
  void setRepeatMode(RepeatMode mode);
  
  // Volume Control
  double get volume;
  void setVolume(double value); // 0.0 to 1.0
}
```

## Implementation Requirements

### Flutter Bridge Architecture
1. **Method Channel**: Use for synchronous calls and simple async operations
2. **Event Channel**: Use for continuous streams (events, royaltyEvents, progress updates)
3. **Error Handling**: Properly map Swift errors to Flutter exceptions
4. **Threading**: Ensure all UI updates happen on main thread
5. **Memory Management**: Proper cleanup of streams and native resources

### Key Implementation Points
1. **Authentication**: The auth function must be callable from Swift and return proper auth payload
2. **Async Operations**: All catalogue methods and player operations are async
3. **State Management**: Player state changes should be streamed to Flutter
4. **Progress Tracking**: Continuous progress updates during playback
5. **Error Resilience**: Handle network failures, expired URLs, and playback errors
6. **Resource Cleanup**: Properly dispose of players and streams

### Platform-Specific Considerations
1. **iOS Audio Session**: Handle interruptions, route changes
2. **Background Playback**: Support background audio if needed
3. **Control Center**: Integration with iOS media controls
4. **Network Handling**: Handle URL expiration and token refresh

### Testing Strategy
1. **Unit Tests**: Test entity serialization/deserialization
2. **Integration Tests**: Test full auth → catalogue → playback flow
3. **Error Scenarios**: Test network failures, auth expiration
4. **Edge Cases**: Empty playlists, malformed responses

## Expected Usage Pattern
```dart
// Initialize SDK
final sdk = MyndSDK(
  authFunction: () async => await getAuthToken(),
  audioConfiguration: AudioConfiguration(),
);

// Browse catalogue
final categories = await sdk.catalogue.getCategories();
final playlists = await sdk.catalogue.getPlaylists(categoryId);
final playlistWithSongs = await sdk.catalogue.getPlaylist(playlistId);

// Control playback
await sdk.player.play(playlistWithSongs);
sdk.player.setVolume(0.8);
sdk.player.setRepeatMode(RepeatMode.all);

// Listen to events
sdk.player.events.listen((event) {
  switch (event) {
    case AudioPlayerEvent.stateChanged(state):
      // Update UI
    case AudioPlayerEvent.progressUpdated(progress):
      // Update progress bar
  }
});
```

## Validation Rules
- All required fields must be non-null and validated
- URLs should be validated before use
- Volume values must be between 0.0 and 1.0
- Duration values should be non-negative
- Proper error logging throughout the bridge
- Handle edge cases like empty playlists gracefully

## Task
Create a complete Flutter plugin that bridges this Swift SDK with proper error handling, state management, and follows Flutter plugin best practices. 