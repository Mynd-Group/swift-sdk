import XCTest
import Combine
@testable import MyndCore

final class CoreAudioPlayerRepeatModeTests: AudioPlayerTestBase {

    // MARK: - Repeat Mode Setting Tests

    func testSetRepeatMode_MustUpdateProperty() {
        XCTAssertEqual(audioPlayer.repeatMode, .none, "MUST start with repeat mode none")

        audioPlayer.setRepeatMode(.all)
        XCTAssertEqual(audioPlayer.repeatMode, .all, "MUST update to repeat all")

        audioPlayer.setRepeatMode(.none)
        XCTAssertEqual(audioPlayer.repeatMode, .none, "MUST update to repeat none")
    }

    // MARK: - Repeat None Behavior Tests

    @MainActor
    func testRepeatNone_MustStopAfterLastSong() async {
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 2)
        audioPlayer.setRepeatMode(.none)

        var completedEvents: [AudioPlayerEvent] = []
        let playlistCompletedExpectation = XCTestExpectation(description: "Playlist must complete")

        audioPlayer.events
            .sink { event in
                completedEvents.append(event)
                if case .playlistCompleted = event {
                    playlistCompletedExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await audioPlayer.play(playlist)

        await fulfillment(of: [playlistCompletedExpectation], timeout: 5.0)

        let playlistCompletedEvents = completedEvents.compactMap { event -> AudioPlayerEvent? in
            if case .playlistCompleted = event { return event }
            return nil
        }

        XCTAssertEqual(playlistCompletedEvents.count, 1, "MUST emit exactly one playlist completed event")
        XCTAssertEqual(audioPlayer.state, .stopped, "MUST be in stopped state after completion")
    }

    @MainActor
    func testRepeatNone_MustEmitSongCompletedEvents() async {
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 2)
        audioPlayer.setRepeatMode(.none)

        var songCompletedEvents: [(Song, Int)] = []
        let expectation = XCTestExpectation(description: "Must receive song completed events")
        expectation.expectedFulfillmentCount = 2

        audioPlayer.events
            .sink { event in
                if case .songCompleted(let song, let index) = event {
                    songCompletedEvents.append((song, index))
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await audioPlayer.play(playlist)

        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertEqual(songCompletedEvents.count, 2, "MUST emit song completed for both songs")
        XCTAssertEqual(songCompletedEvents[0].0.id, "test-song-1", "MUST complete first song")
        XCTAssertEqual(songCompletedEvents[0].1, 0, "MUST have correct index for first song")
        XCTAssertEqual(songCompletedEvents[1].0.id, "test-song-2", "MUST complete second song")
        XCTAssertEqual(songCompletedEvents[1].1, 1, "MUST have correct index for second song")
    }

    // MARK: - Repeat All Behavior Tests

    @MainActor
    func testRepeatAll_MustRestartPlaylist() async {
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 2)
        audioPlayer.setRepeatMode(.all)

        var playlistCompletedCount = 0
        var songCompletedEvents: [(Song, Int)] = []
        let expectation = XCTestExpectation(description: "Must receive multiple playlist completions")
        expectation.expectedFulfillmentCount = 2

        audioPlayer.events
            .sink { event in
                switch event {
                case .playlistCompleted:
                    playlistCompletedCount += 1
                    expectation.fulfill()
                case .songCompleted(let song, let index):
                    songCompletedEvents.append((song, index))
                default:
                    break
                }
            }
            .store(in: &cancellables)

        await audioPlayer.play(playlist)

        await fulfillment(of: [expectation], timeout: 8.0)

        XCTAssertEqual(playlistCompletedCount, 2, "MUST complete playlist twice with repeat all")
        XCTAssertGreaterThanOrEqual(songCompletedEvents.count, 4, "MUST have completed songs from multiple loops")

        let firstLoopSongs = songCompletedEvents.prefix(2)
        let secondLoopSongs = songCompletedEvents.dropFirst(2).prefix(2)

        if secondLoopSongs.count >= 2 {
            XCTAssertEqual(firstLoopSongs.first?.0.id, secondLoopSongs.first?.0.id, "MUST replay same songs")
            XCTAssertEqual(firstLoopSongs.last?.0.id, secondLoopSongs.last?.0.id, "MUST replay same songs")
        }
    }

    @MainActor
    func testRepeatAll_MustMaintainPlayingState() async {
        let playlist = AudioPlayerTestHelpers.createSingleSongPlaylist()
        audioPlayer.setRepeatMode(.all)

        var playlistCompletions = 0
        let expectation = XCTestExpectation(description: "Must receive playlist completions showing repeat works")
        expectation.expectedFulfillmentCount = 2

        audioPlayer.events
            .sink { event in
                if case .playlistCompleted = event {
                    playlistCompletions += 1
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await audioPlayer.play(playlist)

        await fulfillment(of: [expectation], timeout: 8.0)

        XCTAssertEqual(playlistCompletions, 2, "MUST complete playlist twice with repeat all")

        if case .playing = audioPlayer.state {
            XCTAssert(true, "MUST still be playing after repeat")
        } else {
            XCTFail("MUST still be playing after repeat, but state is: \(audioPlayer.state)")
        }
    }

    // MARK: - Repeat Mode Persistence Tests

    @MainActor
    func testRepeatMode_MustPersistAcrossPlaylistChanges() async {
        let playlist1 = AudioPlayerTestHelpers.createSingleSongPlaylist(playlistId: "playlist-1")
        let playlist2 = AudioPlayerTestHelpers.createSingleSongPlaylist(playlistId: "playlist-2")

        audioPlayer.setRepeatMode(.all)
        XCTAssertEqual(audioPlayer.repeatMode, .all, "MUST set repeat mode")

        await audioPlayer.play(playlist1)
        XCTAssertEqual(audioPlayer.repeatMode, .all, "MUST persist repeat mode after play")

        await audioPlayer.stop()
        XCTAssertEqual(audioPlayer.repeatMode, .all, "MUST persist repeat mode after stop")

        await audioPlayer.play(playlist2)
        XCTAssertEqual(audioPlayer.repeatMode, .all, "MUST persist repeat mode with new playlist")
    }

    @MainActor
    func testRepeatMode_MustPersistAcrossPauseResume() async {
        let playlist = AudioPlayerTestHelpers.createSingleSongPlaylist()
        audioPlayer.setRepeatMode(.all)

        await audioPlayer.play(playlist)
        try? await Task.sleep(for: .milliseconds(200))

        audioPlayer.pause()
        XCTAssertEqual(audioPlayer.repeatMode, .all, "MUST persist repeat mode after pause")

        audioPlayer.resume()
        XCTAssertEqual(audioPlayer.repeatMode, .all, "MUST persist repeat mode after resume")
    }

    // MARK: - Comprehensive End-to-End Test

    @MainActor
    func testRepeatMode_EndToEndWorkflow() async {
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 2)

        var allEvents: [AudioPlayerEvent] = []

        audioPlayer.events
            .sink { event in
                allEvents.append(event)
                print("Event received: \(event)")
            }
            .store(in: &cancellables)

        // Test 1: Default repeat none behavior
        XCTAssertEqual(audioPlayer.repeatMode, .none, "MUST start with repeat none")

        await audioPlayer.play(playlist)
        try? await Task.sleep(for: .seconds(4))

        let noneEvents = allEvents
        let noneCompletions = noneEvents.compactMap { event -> AudioPlayerEvent? in
            if case .playlistCompleted = event { return event }
            return nil
        }

        XCTAssertEqual(noneCompletions.count, 1, "MUST complete once with repeat none")
        XCTAssertEqual(audioPlayer.state, .stopped, "MUST stop with repeat none")

        // Test 2: Switch to repeat all
        await audioPlayer.stop()
        allEvents.removeAll()

        audioPlayer.setRepeatMode(.all)
        XCTAssertEqual(audioPlayer.repeatMode, .all, "MUST set repeat all")

        await audioPlayer.play(playlist)
        try? await Task.sleep(for: .seconds(6))

        let allEvents_repeatAll = allEvents
        let repeatCompletions = allEvents_repeatAll.compactMap { event -> AudioPlayerEvent? in
            if case .playlistCompleted = event { return event }
            return nil
        }

        XCTAssertGreaterThanOrEqual(repeatCompletions.count, 2, "MUST complete multiple times with repeat all")

        if case .playing = audioPlayer.state {
            XCTAssert(true, "MUST still be playing with repeat all")
        } else {
            XCTFail("MUST still be playing with repeat all, but state is: \(audioPlayer.state)")
        }

        print("End-to-end test completed successfully")
    }
}