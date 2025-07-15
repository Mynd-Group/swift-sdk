import Foundation

protocol RequestClientProtocol {
    func get<T: Decodable>(_ url: URL, completion: @escaping (Result<T, Error>) -> Void)
    func post<T: Decodable>(_ url: URL, body: Data, completion: @escaping (Result<T, Error>) -> Void)
}

public class RequestClient: RequestClientProtocol {
    func get<T>(_: URL, completion _: @escaping (Result<T, any Error>) -> Void) where T: Decodable {}

    func post<T>(_: URL, body _: Data, completion _: @escaping (Result<T, any Error>) -> Void) where T: Decodable {}

    public init() {}
}
