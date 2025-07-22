import XCTest
import Combine
@testable import MyndCore

class AudioPlayerTestHelpers {

    static func createTestPlaylist(songCount: Int = 2, playlistId: String = "test-playlist") -> PlaylistWithSongs {
        let songs = (1...songCount).map { index in
            Song(
                id: "test-song-\(index)",
                name: "Test Song \(index)",
                image: nil,
                audio: Audio(
                    hls: SongHLS(
                        id: "hls-\(index)",
                        url: "http://codeskulptor-demos.commondatastorage.googleapis.com/pang/arrow.mp3",
                        durationInSeconds: 1,
                        urlExpiresAtISO: "2025-12-31T23:59:59Z"
                    ),
                    mp3: SongMP3(
                        id: "mp3-\(index)",
                        url: "http://codeskulptor-demos.commondatastorage.googleapis.com/pang/arrow.mp3",
                        durationInSeconds: 1,
                        urlExpiresAtISO: "2025-12-31T23:59:59Z"
                    )
                ),
                artists: [
                    Artist(id: "artist-\(index)", name: "Test Artist \(index)")
                ]
            )
        }

        let playlist = Playlist(
            id: playlistId,
            name: "Test Playlist",
            image: nil,
            description: "A test playlist",
            instrumentation: nil,
            genre: nil,
            bpm: nil
        )

        return PlaylistWithSongs(playlist: playlist, songs: songs)
    }

    static func createSingleSongPlaylist(songId: String = "test-song-1", playlistId: String = "test-playlist-single") -> PlaylistWithSongs {
        return createTestPlaylist(songCount: 1, playlistId: playlistId)
    }

    static func createTestSong(id: String = "test-song", name: String = "Test Song") -> Song {
        return Song(
            id: id,
            name: name,
            image: nil,
            audio: Audio(
                hls: SongHLS(
                    id: "hls-\(id)",
                    url: "http://codeskulptor-demos.commondatastorage.googleapis.com/pang/arrow.mp3",
                    durationInSeconds: 1,
                    urlExpiresAtISO: "2025-12-31T23:59:59Z"
                ),
                mp3: SongMP3(
                    id: "mp3-\(id)",
                    url: "http://codeskulptor-demos.commondatastorage.googleapis.com/pang/arrow.mp3",
                    durationInSeconds: 1,
                    urlExpiresAtISO: "2025-12-31T23:59:59Z"
                )
            ),
            artists: [
                Artist(id: "artist-\(id)", name: "Test Artist")
            ]
        )
    }
}

class AudioPlayerTestBase: XCTestCase {

    var audioPlayer: CoreAudioPlayer!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        audioPlayer = CoreAudioPlayer()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables.removeAll()
        audioPlayer = nil
        super.tearDown()
    }
}