import AVFoundation
import Combine
import MediaPlayer

private let log = Logger(prefix: "RouteHandler")

struct RouteHandler {
    private var cancellable: AnyCancellable?
    private(set) var isEnabled = false

    mutating func enable(
        onRouteChange: @escaping (AVAudioSession.RouteChangeReason, AVAudioSessionRouteDescription, AVAudioSessionRouteDescription) -> Void = { reason, current, previous in
            #if os(iOS)
            log.debug("Default route change handler: reason=\(reason), current=\(current), previous=\(previous)")
            #endif
        }
    ) {
        guard !isEnabled else { return }
        isEnabled = true

        #if os(iOS)
        cancellable = NotificationCenter.default.publisher(
            for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard
                    let userInfo = notification.userInfo,
                    let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                    let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
                else {
                    log.error("Route change notification missing required data")
                    return
                }

                let currentRoute = AVAudioSession.sharedInstance().currentRoute

                // Get previous route if available
                let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
                    ?? currentRoute

                onRouteChange(reason, currentRoute, previousRoute)
                log.debug("Route change handled: \(reason)")
            }

        log.debug("Route handler enabled")
        #endif
    }

    mutating func disable() {
        guard isEnabled else { return }
        isEnabled = false
        cancellable?.cancel()
        cancellable = nil
        log.debug("Route handler disabled")
    }
}