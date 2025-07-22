import XCTest
import Combine
import AVFoundation
@testable import MyndCore

final class CoreAudioPlayerProgressTests: AudioPlayerTestBase {

    // MARK: - Initial Progress State Tests

    func testInitialProgress_MustBeZero() {
        let progress = audioPlayer.progress

        XCTAssertEqual(progress.trackCurrentTime, 0, "MUST start with zero track current time")
        XCTAssertEqual(progress.trackDuration, 0, "MUST start with zero track duration")
        XCTAssertEqual(progress.trackIndex, 0, "MUST start with zero track index")
        XCTAssertEqual(progress.playlistCurrentTime, 0, "MUST start with zero playlist current time")
        XCTAssertEqual(progress.playlistDuration, 0, "MUST start with zero playlist duration")
        XCTAssertEqual(progress.trackProgress, 0, "MUST start with zero track progress")
        XCTAssertEqual(progress.playlistProgress, 0, "MUST start with zero playlist progress")
    }

    // MARK: - Progress Updates Tests

    @MainActor
    func testProgressUpdates_MustBeConsistentAndValid() async {
        // Given
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 1)
        var progressUpdates: [PlaybackProgress] = []

        let expectation = XCTestExpectation(description: "Must receive multiple progress updates")
        expectation.expectedFulfillmentCount = 3

        audioPlayer.events
            .sink { event in
                if case .progressUpdated(let progress) = event {
                    progressUpdates.append(progress)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        await audioPlayer.play(playlist)

        // Then
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertGreaterThanOrEqual(progressUpdates.count, 3, "MUST receive multiple progress updates")

        let firstProgress = progressUpdates.first!
        XCTAssertEqual(firstProgress.trackIndex, 0, "MUST start at track index 0")
        XCTAssertGreaterThanOrEqual(firstProgress.trackCurrentTime, 0, "MUST have valid current time")
        XCTAssertGreaterThan(firstProgress.trackDuration, 0, "MUST have valid duration")
        XCTAssertGreaterThanOrEqual(firstProgress.trackProgress, 0, "MUST have valid progress")
        XCTAssertLessThanOrEqual(firstProgress.trackProgress, 1, "MUST not exceed 100% progress")

        // Verify progress increases over time
        if progressUpdates.count >= 2 {
            let firstTime = progressUpdates[0].trackCurrentTime
            let lastTime = progressUpdates.last!.trackCurrentTime
            XCTAssertGreaterThanOrEqual(lastTime, firstTime, "MUST show progress over time")
        }
    }

    @MainActor
    func testProgressUpdates_MustUpdateTrackIndex() async {
        // Given
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 2)
        var progressUpdates: [PlaybackProgress] = []
        var trackIndices: Set<Int> = []

        let expectation = XCTestExpectation(description: "Must receive progress updates for different tracks")
        expectation.expectedFulfillmentCount = 6 // Multiple updates across 2 tracks

        audioPlayer.events
            .sink { event in
                if case .progressUpdated(let progress) = event {
                    progressUpdates.append(progress)
                    trackIndices.insert(progress.trackIndex)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        await audioPlayer.play(playlist)

        // Then
        await fulfillment(of: [expectation], timeout: 8.0)

        XCTAssertTrue(trackIndices.contains(0), "MUST have progress updates for track 0")
        XCTAssertTrue(trackIndices.contains(1), "MUST have progress updates for track 1")

        // Verify track index changes correctly
        let track0Updates = progressUpdates.filter { $0.trackIndex == 0 }
        let track1Updates = progressUpdates.filter { $0.trackIndex == 1 }

        XCTAssertGreaterThan(track0Updates.count, 0, "MUST have updates for first track")
        XCTAssertGreaterThan(track1Updates.count, 0, "MUST have updates for second track")
    }

    // MARK: - Playlist Progress Tests

    @MainActor
    func testPlaylistProgress_MustAccumulateCorrectly() async {
        // Given
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 2)
        var progressUpdates: [PlaybackProgress] = []

        let expectation = XCTestExpectation(description: "Must receive playlist progress updates")
        expectation.expectedFulfillmentCount = 4

        audioPlayer.events
            .sink { event in
                if case .progressUpdated(let progress) = event {
                    progressUpdates.append(progress)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        await audioPlayer.play(playlist)

        // Then
        await fulfillment(of: [expectation], timeout: 8.0)

        // Find progress updates for each track
        let track0Updates = progressUpdates.filter { $0.trackIndex == 0 }
        let track1Updates = progressUpdates.filter { $0.trackIndex == 1 }

        if let track0Progress = track0Updates.first, let track1Progress = track1Updates.first {
            // Playlist duration should be sum of track durations
            XCTAssertGreaterThan(track0Progress.playlistDuration, track0Progress.trackDuration,
                                "Playlist duration MUST be greater than single track duration")

            // Playlist current time should increase across tracks
            XCTAssertGreaterThan(track1Progress.playlistCurrentTime, track0Progress.playlistCurrentTime,
                                "Playlist current time MUST increase across tracks")

            // Verify playlist progress bounds
            XCTAssertGreaterThanOrEqual(track0Progress.playlistProgress, 0, "Playlist progress MUST be >= 0")
            XCTAssertLessThanOrEqual(track0Progress.playlistProgress, 1, "Playlist progress MUST be <= 1")
            XCTAssertGreaterThanOrEqual(track1Progress.playlistProgress, 0, "Playlist progress MUST be >= 0")
            XCTAssertLessThanOrEqual(track1Progress.playlistProgress, 1, "Playlist progress MUST be <= 1")
        }
    }

    // MARK: - Progress During State Changes Tests

    @MainActor
    func testProgress_MustPersistDuringPause() async {
        // Given
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 1)
        await audioPlayer.play(playlist)

        // Wait for some progress
        try? await Task.sleep(for: .milliseconds(300))

        let progressBeforePause = audioPlayer.progress
        XCTAssertGreaterThan(progressBeforePause.trackCurrentTime, 0, "MUST have some progress before pause")

        // When
        audioPlayer.pause()

        // Wait a bit while paused
        try? await Task.sleep(for: .milliseconds(200))

        // Then
        let progressAfterPause = audioPlayer.progress
        XCTAssertEqual(progressAfterPause.trackIndex, progressBeforePause.trackIndex, "MUST maintain track index")
        XCTAssertEqual(progressAfterPause.trackDuration, progressBeforePause.trackDuration, "MUST maintain track duration")

        // Progress should not advance significantly while paused
        let timeDifference = abs(progressAfterPause.trackCurrentTime - progressBeforePause.trackCurrentTime)
        XCTAssertLessThan(timeDifference, 0.1, "MUST not advance significantly while paused")
    }

    @MainActor
    func testProgress_MustResumeCorrectly() async {
        // Given
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 1)
        await audioPlayer.play(playlist)

        // Pause after some progress
        try? await Task.sleep(for: .milliseconds(300))
        audioPlayer.pause()

        let progressAfterPause = audioPlayer.progress

        // When
        audioPlayer.resume()

        // Wait for progress to resume
        try? await Task.sleep(for: .milliseconds(300))

        // Then
        let progressAfterResume = audioPlayer.progress
        XCTAssertEqual(progressAfterResume.trackIndex, progressAfterPause.trackIndex, "MUST maintain track index")
        XCTAssertGreaterThanOrEqual(progressAfterResume.trackCurrentTime, progressAfterPause.trackCurrentTime,
                                   "MUST continue from paused position")
    }

    @MainActor
    func testProgress_MustResetOnStop() async {
        // Given
        let playlist = AudioPlayerTestHelpers.createTestPlaylist(songCount: 2)
        await audioPlayer.play(playlist)

        // Wait for some progress
        try? await Task.sleep(for: .milliseconds(500))

        let progressBeforeStop = audioPlayer.progress
        XCTAssertGreaterThan(progressBeforeStop.trackCurrentTime, 0, "MUST have progress before stop")

        // When
        await audioPlayer.stop()

        // Then
        let progressAfterStop = audioPlayer.progress
        XCTAssertEqual(progressAfterStop.trackCurrentTime, 0, "MUST reset track current time")
        XCTAssertEqual(progressAfterStop.trackDuration, 0, "MUST reset track duration")
        XCTAssertEqual(progressAfterStop.trackIndex, 0, "MUST reset track index")
        XCTAssertEqual(progressAfterStop.playlistCurrentTime, 0, "MUST reset playlist current time")
        XCTAssertEqual(progressAfterStop.playlistDuration, 0, "MUST reset playlist duration")
        XCTAssertEqual(progressAfterStop.trackProgress, 0, "MUST reset track progress")
        XCTAssertEqual(progressAfterStop.playlistProgress, 0, "MUST reset playlist progress")
    }

    // MARK: - Progress Calculation Tests

    func testProgressCalculation_MustBeAccurate() {
        // Given
        let progress = PlaybackProgress(
            trackCurrentTime: 30,
            trackDuration: 120,
            trackIndex: 0,
            playlistCurrentTime: 90,
            playlistDuration: 300
        )

        // Then
        XCTAssertEqual(progress.trackProgress, 0.25, accuracy: 0.01, "MUST calculate track progress correctly")
        XCTAssertEqual(progress.playlistProgress, 0.3, accuracy: 0.01, "MUST calculate playlist progress correctly")
    }

    func testProgressCalculation_MustHandleEdgeCases() {
        // Test zero duration
        let zeroProgress = PlaybackProgress(
            trackCurrentTime: 0,
            trackDuration: 0,
            trackIndex: 0,
            playlistCurrentTime: 0,
            playlistDuration: 0
        )

        XCTAssertEqual(zeroProgress.trackProgress, 0, "MUST handle zero duration")
        XCTAssertEqual(zeroProgress.playlistProgress, 0, "MUST handle zero playlist duration")

        // Test complete track
        let completeProgress = PlaybackProgress(
            trackCurrentTime: 100,
            trackDuration: 100,
            trackIndex: 0,
            playlistCurrentTime: 100,
            playlistDuration: 100
        )

        XCTAssertEqual(completeProgress.trackProgress, 1.0, "MUST handle complete track")
        XCTAssertEqual(completeProgress.playlistProgress, 1.0, "MUST handle complete playlist")
    }
}
