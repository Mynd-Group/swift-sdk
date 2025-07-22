import AVFoundation
import Combine
import MediaPlayer

// MARK: — InterruptionHandler
struct InterruptionHandler {
    private var cancellable: AnyCancellable?
    private(set) var isEnabled = false
    
    mutating func enable(_ callback: @escaping (Notification) -> Void) {
        guard !isEnabled else { return }
        isEnabled = true

      #if os(iOS)
        cancellable = NotificationCenter.default.publisher(
            for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: callback)
        #endif

    }
    
    mutating func disable() {
        isEnabled = false
        cancellable?.cancel()
        cancellable = nil
    }
}
