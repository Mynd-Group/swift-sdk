import AVFoundation
import Combine
import MediaPlayer

private let log = Logger(prefix: "CommandCenterHandler")

struct CommandCenterHandler {
    private(set) var isEnabled = false

    mutating func enable(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onTogglePlayPause: @escaping () -> Void
    ) {
        guard !isEnabled else { return }
        isEnabled = true

        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        // Enable play/pause controls with callbacks
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            onPlay()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            onPause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            onTogglePlayPause()
            return .success
        }

        // Disable seeking and skipping
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false

        log.debug("Command center enabled with play/pause callbacks")
        #endif
    }
}
