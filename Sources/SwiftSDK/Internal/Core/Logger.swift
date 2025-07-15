
protocol LoggerProtocol {
    func info(_ message: String, dictionary: [String: Any]?)
    func warn(_ message: String, dictionary: [String: Any]?)
    func error(_ message: String, dictionary: [String: Any]?)
    func debug(_ message: String, dictionary: [String: Any]?)
}

struct Logger: LoggerProtocol {
    let prefix: String

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
        var logMessage = "[\(level)] [\(prefix)] \(message)"
        if let dict = dictionary {
            logMessage += " - \(dict)"
        }
        print(logMessage)
    }
}
