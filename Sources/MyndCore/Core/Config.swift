import Foundation

protocol ConfigProtocol {
    static var baseUrl: URL { get }
}

struct Config: ConfigProtocol {
    public static let baseUrl: URL = {
        guard let url = URL(string: "https://noted-fluent-termite.ngrok-free.app/api/v1") else {
            fatalError("Invalid base URL configuration")
        }
        return url
    }()
}
