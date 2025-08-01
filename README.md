# MyndSDK

> ⚠️ **EARLY BETA SOFTWARE** ⚠️
> 
> **This SDK is currently in early beta development. Expect bugs, breaking changes, and incomplete features.**
> 
> - 🔄 **Breaking Changes**: API may change significantly between versions
> - 📝 **Incomplete Documentation**: Some features may be undocumented
> - 🧪 **Testing Required**: Thoroughly test all functionality in your use case
> - 💬 **Feedback Welcome**: Please report issues and provide feedback
> 

A comprehensive iOS SDK for music streaming and playback, providing seamless integration with the Myndstream platform.

## Overview

MyndSDK enables iOS applications to access curated music content through a robust catalogue system and high-quality audio playback engine. The SDK handles authentication, content discovery, and media playback with built-in background audio support.

## Core Features

### 🎵 Music Catalogue
- Browse organized music categories
- Access curated playlists with metadata (genre, BPM, instrumentation)
- Retrieve individual songs with artist information
- High-resolution artwork support

### 🎧 Audio Playback
- AVFoundation-based streaming engine
- Background playback with MediaPlayer integration
- Support for HLS and MP3 formats
- Volume control and repeat modes
- Real-time progress tracking
- Royalty tracking events

### 🔐 Authentication
- Token-based authentication with automatic refresh
- Thread-safe token management
- Configurable HTTP client with retry logic

## Quick Start

### Authentication Setup

Before using the SDK, you need to set up authentication through your backend. The MyndSDK requires a refresh token to initialize, which must be obtained by calling the Myndstream API from your secure backend endpoint.

**Important**: Never store API keys or make direct calls to the Myndstream API from your mobile app for security reasons.

#### Backend Integration Required

1. **Create a secure endpoint** in your backend that:
   - Accepts your user's identifier
   - Calls the Myndstream authentication API using your API key
   - Returns the authentication tokens to your app

2. **Your mobile app** should:
   - Call your backend endpoint
   - Receive the refresh token
   - Use it to initialize the MyndSDK

#### Example Implementation

**Your Backend Endpoint** (conceptual):
```
POST /api/auth/myndstream

1. Authenticate the incoming request using your existing auth system
2. Extract the authenticated user's ID
3. Make a request to Myndstream API:

   POST https://app.myndstream.com/api/v1/integration-user/authenticate
   Headers:
     x-api-key: YOUR_MYNDSTREAM_API_KEY
     Content-Type: application/json
   Body:
     {
       "providerUserId": "authenticated_user_id"
     }

4. Return the authentication response to your mobile app
```

**Your iOS App**:
```swift
import MyndCore

// 1. Call your backend endpoint to get Myndstream tokens
func getMyndstreamRefreshToken() async throws -> String {
    // Implementation depends on your networking layer and auth system
    // - Make authenticated request to your backend
    // - Parse the response to extract refreshToken
    // - Return the refreshToken string
}

// 2. Initialize SDK with the refresh token
@MainActor
func initializeSDK() async throws -> MyndSDK {
    let refreshToken = try await getMyndstreamRefreshToken()
    return MyndSDK(refreshToken: refreshToken)
}
```

### Installation

The SDK is distributed via CocoaPods.

**For app projects**, add the dependency to your `Podfile`:

```ruby
pod 'MyndCore', '~> 1.1.0'
```

**For library/framework projects**, add the dependency to your `.podspec`:

```ruby
s.dependency 'MyndCore', '1.1.0'
```

Then run:
```bash
pod install
```

### Basic Usage

```swift
import MyndCore

// Initialize SDK
@MainActor
let sdk = MyndSDK(refreshToken: "your_refresh_token")

// Browse catalogue
let categories = try await sdk.catalogue.getCategories()
let playlists = try await sdk.catalogue.getPlaylists(categoryId: nil)

// Play music
let playlistWithSongs = try await sdk.catalogue.getPlaylist(playlistId: "playlist_id")
await sdk.player.play(playlistWithSongs)

// Control playback
sdk.player.pause()
sdk.player.resume()
sdk.player.setVolume(0.8)

// Monitor playback events
sdk.player.events
    .sink { event in
        switch event {
        case .stateChanged(let state):
            handleStateChange(state)
        case .progressUpdated(let progress):
            updateUI(progress)
        case .errorOccurred(let error):
            handleError(error)
        default:
            break
        }
    }
    .store(in: &cancellables)
```

## API Reference

### MyndSDK

Main entry point providing access to catalogue and playback functionality.

```swift
public final class MyndSDK {
    public let catalogue: CatalogueClientProtocol
    public let player: AudioClientProtocol
    
    @MainActor
    public init(
        refreshToken: String,
        audioConfiguration: AudioClient.Configuration = .init()
    )
}
```

### Catalogue Client

```swift
public protocol CatalogueClientProtocol: Sendable {
    func getCategories() async throws -> [Category]
    func getCategory(categoryId: String) async throws -> Category
    func getPlaylists(categoryId: String?) async throws -> [Playlist]
    func getPlaylist(playlistId: String) async throws -> PlaylistWithSongs
}
```

### Audio Player

```swift
@MainActor
public protocol AudioClientProtocol: AnyObject {
    var events: AnyPublisher<AudioPlayerEvent, Never> { get }
    var royaltyEvents: AnyPublisher<RoyaltyTrackingEvent, Never> { get }
    var state: PlaybackState { get }
    var progress: PlaybackProgress { get }
    var isPlaying: Bool { get }
    var currentSong: Song? { get }
    var currentPlaylist: PlaylistWithSongs? { get }
    var volume: Float { get }

    func play(_ playlist: PlaylistWithSongs) async
    func pause()
    func resume()
    func stop() async
    func setRepeatMode(_ mode: RepeatMode)
    func setVolume(_ value: Float)
}
```

## Data Models

### Song
```swift
public struct Song {
    public let id: String
    public let name: String
    public let image: SongImage?
    public let audio: Audio           // HLS and MP3 URLs
    public let artists: [Artist]
    public let instrumentation: String?
    public let genre: String?
    public let bpm: Int?
    public let durationInSeconds: Int
}
```

### Playlist
```swift
public struct Playlist {
    public let id: String
    public let name: String
    public let image: PlaylistImage?
    public let description: String?
    public let instrumentation: String?
    public let genre: String?
    public let bpm: Int?
}
```

### Category
```swift
public struct Category {
    public let id: String
    public let name: String
    public let image: CategoryImage?
}
```

## Playback Events

### Audio Player Events
- `PlaylistQueued` - New playlist loaded
- `StateChanged` - Playback state transitions
- `ProgressUpdated` - Position updates
- `PlaylistCompleted` - End of playlist
- `SongNetworkStalled` - Network buffering
- `SongNetworkFailure` - Stream error
- `ErrorOccurred` - General errors
- `VolumeChanged` - Volume adjustments

### Royalty Tracking Events
- `TrackStarted` - Song playback begins
- `TrackProgress` - Playback progress milestones
- `TrackFinished` - Song completion

## Requirements

- **Minimum iOS:** 14.0
- **Swift:** 5.0+
- **Xcode:** 14.0+

## Dependencies

- Foundation
- AVFoundation
- MediaPlayer
- Combine

## Thread Safety

The SDK is designed for concurrent access:
- Authentication tokens are managed with actor synchronization
- All `AudioClientProtocol` methods must be called from the main actor
- `CatalogueClientProtocol` methods are sendable and thread-safe
- Event publishers deliver events on the main queue

## Configuration

Customize audio behavior with `AudioClient.Configuration`:

```swift
public struct Configuration: Sendable {
    public var handleInterruptions: Bool = true
    public var handleInfoItemUpdates: Bool = true
    public var handleAudioSession: Bool = true
    public var handleCommandCenter: Bool = true
}
```

## Error Handling

All catalogue operations use Swift's error handling with `async throws`. Playback errors are delivered through the events publisher.

```swift
do {
    let categories = try await sdk.catalogue.getCategories()
} catch {
    console.log("Failed to fetch categories: \(error)")
}
```

## License

Proprietary - Myndstream Platform 