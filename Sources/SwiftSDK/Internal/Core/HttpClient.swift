import Foundation
import Combine

public protocol HttpClientProtocol: Sendable {
    nonisolated func get<R: Decodable>(
        _ url: URL,
        headers: [String: String]?
    ) async throws -> R

    nonisolated func post<B: Encodable, R: Decodable>(
        _ url: URL,
        body: B,
        headers: [String: String]?
    ) async throws -> R
}


public final class HttpClient: HttpClientProtocol {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        session: URLSession = .shared,
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init()
    ) {
        self.session  = session
        self.encoder  = encoder
        self.decoder  = decoder
    }

    public nonisolated func get<R: Decodable>(
        _ url: URL,
        headers: [String: String]? = nil
    ) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(R.self, from: data)
    }

     public nonisolated func post<B: Encodable, R: Decodable>(
        _ url: URL,
        body: B,
        headers: [String: String]? = nil
    ) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw error
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(R.self, from: data)
    }

    private func dataTask<R: Decodable>(
        _ request: URLRequest
    ) -> AnyPublisher<R, Error> {
        session.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let http = response as? HTTPURLResponse,
                      200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            .decode(type: R.self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}