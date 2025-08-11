import Combine
import Foundation
import MyndCore

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAtUnixMs: Int
}

public func authFn() async throws -> AuthPayloadProtocol {
    guard let url = URL(string: "https://staging.app.myndstream.com/api/v1/integration-user/authenticate") else {
        print("Invalid URL")
        throw URLError(.badURL)
    }

    let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbnRlZ3JhdGlvbkFwaUtleUlkIjoiZmIxZjM1ZTYtM2ZkNy00MWQ3LWIwZWUtNGYxYzY3ZjY2NjU2IiwiYWNjb3VudElkIjoiMTBlOTlmMzAtNDlkNy00ZDljLWFiMWEtMmU2MjYxMTk2YTRiIiwiaWF0IjoxNzU0OTE3NTU1fQ.u1wryXvdoWmvYFr33vD3kc-eyH2JhEMTpDTXhaVrqS0"

    let requestBody = ["providerUserId": "some-random-id"]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    } catch {
        print("Failed to serialize request body: \(error)")
        throw error
    }

    print("Making auth request to: \(url)")

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("Auth response status: \(httpResponse.statusCode)")

            guard 200...299 ~= httpResponse.statusCode else {
                print("Auth request failed with status: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Response body: \(responseString)")
                }
                throw URLError(.badServerResponse)
            }
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        print("Auth successful, token expires at: \(authResponse.accessTokenExpiresAtUnixMs)")

        return MyndCore.AuthPayload(
            accessToken: authResponse.accessToken,
            refreshToken: authResponse.refreshToken,
            accessTokenExpiresAtUnixMs: authResponse.accessTokenExpiresAtUnixMs
        )

    } catch {
        print("Auth request failed: \(error)")
        throw error
    }
}
