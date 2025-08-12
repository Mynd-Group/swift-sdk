import Combine
import Foundation
import MyndCore

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAtUnixMs: Int
}

public func authFn() async throws -> AuthPayloadProtocol {
    guard let url = URL(string: "http://localhost:4000/api/v1/integration-user/authenticate") else {
        print("Invalid URL")
        throw URLError(.badURL)
    }

    let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbnRlZ3JhdGlvbkFwaUtleUlkIjoiMzMyNzE5NzctOWRhYS00YjJhLWFkODQtYWNlZjU0MzQ3ZmQ3IiwiYWNjb3VudElkIjoiMTBlOTlmMzAtNDlkNy00ZDljLWFiMWEtMmU2MjYxMTk2YTRiIiwiaWF0IjoxNzU1MDA5ODI0fQ.H0eYYVzPJpSvs_ys6OgexgsOaaMVo3tQuEbP0DfSnbw"

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
