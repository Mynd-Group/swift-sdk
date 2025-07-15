import SwiftSDK

public func authFn() async -> AuthPayload {
    return AuthPayload(
        accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbnRlZ3JhdGlvbklkIjoiYjI4MGFlNTEtMmJlMy00ZmU1LWE4NjYtZGQ1YmM1ODhlZmE3IiwiaW50ZWdyYXRpb25Vc2VySWQiOiJlNzIwNzcyNy02ZjgyLTQ0NTMtYWQ1Yi00MmYwN2E1NmU1ZWUiLCJhY2NvdW50SWQiOiIxMGU5OWYzMC00OWQ3LTRkOWMtYWIxYS0yZTYyNjExOTZhNGIiLCJyZWZyZXNoVG9rZW5JZCI6IjE2YmZiZDU2LWE5YmMtNGI5YS04N2Y3LTE2YmE0NGY2ZTkxOCIsImludGVncmF0aW9uQXBpS2V5SWQiOiJlMGYzNDViYS1hZGJiLTQ5ZTgtYTY2My1mOTE3MjNhNzQ4ZDEiLCJpYXQiOjE3NTI1OTcxMTUsImV4cCI6MTc1MjU5ODkxNX0.YoajeIJWiB3K6jWBM1INE8Q_1eEs7Z5o5XrpBMXqF00", refreshToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbnRlZ3JhdGlvbklkIjoiYjI4MGFlNTEtMmJlMy00ZmU1LWE4NjYtZGQ1YmM1ODhlZmE3IiwiaW50ZWdyYXRpb25Vc2VySWQiOiJlNzIwNzcyNy02ZjgyLTQ0NTMtYWQ1Yi00MmYwN2E1NmU1ZWUiLCJhY2NvdW50SWQiOiIxMGU5OWYzMC00OWQ3LTRkOWMtYWIxYS0yZTYyNjExOTZhNGIiLCJyZWZyZXNoVG9rZW5JZCI6IjE2YmZiZDU2LWE5YmMtNGI5YS04N2Y3LTE2YmE0NGY2ZTkxOCIsImludGVncmF0aW9uQXBpS2V5SWQiOiJlMGYzNDViYS1hZGJiLTQ5ZTgtYTY2My1mOTE3MjNhNzQ4ZDEiLCJpYXQiOjE3NTI1OTcxMTUsImV4cCI6MTc1MjY4MzUxNX0.BWO_s8dogiZLcUaINwmkQJFEtXdyWERL3lQtsv-J0zM", accessTokenExpiresAtUnixMs: 1_752_598_615_359
    )
}

@main
struct CLI {
    static func main() async {
        do {
            let sdk = SwiftSDK(authFunction: authFn)
            let categories = try await sdk.catalogue.getCategories()
            print("Retrieved \(categories.count) categories")
            for category in categories {
                let categoryRes = try await sdk.catalogue.getCategory(categoryId: category.id)
                print("Category: \(categoryRes)")
                let playlists = try await sdk.catalogue.getPlaylists(categoryId: category.id)
                for playlist in playlists {
                    let playlistRes = try await sdk.catalogue.getPlaylist(playlistId: playlist.id)
                    print("Playlist: \(playlistRes)")
                    for song in playlistRes.songs {
                        print("Song: \(song.name)")
                    }
                }
            }
        } catch {
            print("Error: \(error)")
        }
    }
}
