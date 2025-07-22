import AVFoundation
import Combine
import MediaPlayer

private let log = Logger(prefix: "AudioSessionHandler")
// MARK: — AudioSessionHandler
struct AudioSessionHandler {

#if os(iOS)
    func activate(
        options: [AVAudioSession.CategoryOptions] = [],
        mode: AVAudioSession.Mode = .default,
        category: AVAudioSession.Category = .playback
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(category, mode: mode, options: AVAudioSession.CategoryOptions(options))
        try session.setActive(true)
        log.debug("Audio session activated")
    }



    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false)
        log.debug("Audio session deactivated")
    }
#endif
}
