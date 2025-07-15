import Foundation

public protocol ConfigProtocol {
    static var baseUrl: URL { get }
}

struct Config: ConfigProtocol {
    public static let baseUrl: URL = .init(string: "http://localhost:4000/api/v1")!
}

