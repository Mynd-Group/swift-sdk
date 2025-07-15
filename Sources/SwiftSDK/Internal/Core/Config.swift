import Foundation

public protocol ConfigProtocol {
    static var baseUrl: URL { get }
}

struct Config: ConfigProtocol {
   public static let baseUrl: URL = URL(string: "https://api.example.com")!
}