import Foundation

protocol LoggerProtocol: Sendable {
    func info(_ message: String, dictionary: [String: Any]?)
    func warn(_ message: String, dictionary: [String: Any]?)
    func error(_ message: String, dictionary: [String: Any]?)
    func debug(_ message: String, dictionary: [String: Any]?)
}

struct Logger: LoggerProtocol, Sendable {
    let prefix: String
    
    // Cached formatter for performance
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init(prefix: String = "") {
        self.prefix = prefix
    }

    func info(_ message: String, dictionary: [String: Any]? = nil) {
        log(level: "INFO", message: message, dictionary: dictionary)
    }

    func warn(_ message: String, dictionary: [String: Any]? = nil) {
        log(level: "WARN", message: message, dictionary: dictionary)
    }

    func error(_ message: String, dictionary: [String: Any]? = nil) {
        log(level: "ERROR", message: message, dictionary: dictionary)
    }

    func debug(_ message: String, dictionary: [String: Any]? = nil) {
        log(level: "DEBUG", message: message, dictionary: dictionary)
    }

    private func log(level: String, message: String, dictionary: [String: Any]?) {
        let timestamp = Self.timeFormatter.string(from: Date())
        let threadInfo = getCurrentThreadInfo()
        
        var logMessage = "[\(timestamp)] [\(level)] [\(threadInfo)] [\(prefix)] \(message)"
        if let dict = dictionary {
            logMessage += " - \(dict)"
        }
        print(logMessage)
    }
    
    private func getCurrentThreadInfo() -> String {
        if Thread.isMainThread {
            return "Main"
        }
        
        
        // Check if we're on a dispatch queue
        if let queueName = getCurrentQueueName() {
            return queueName
        }
        
        // Fall back to thread description
        return "BG-THREAD"
    }
    
    private func getCurrentQueueName() -> String? {
        let name = __dispatch_queue_get_label(nil)
        return String(cString: name, encoding: .utf8)
    }
}
