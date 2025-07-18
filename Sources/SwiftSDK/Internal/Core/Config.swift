import Foundation

public protocol ConfigProtocol {
    static var baseUrl: URL { get }
}

struct Config: ConfigProtocol {
    public static let baseUrl: URL = {
        guard let url = URL(string: "http://127.0.0.1:4000/api/v1") else {
            fatalError("Invalid base URL configuration")
        }
        return url
    }()
}

