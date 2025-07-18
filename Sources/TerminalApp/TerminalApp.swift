import SwiftSDK

public func authFn() async -> AuthPayload {
    return AuthPayload(
        accessToken:
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbnRlZ3JhdGlvbklkIjoiYjI4MGFlNTEtMmJlMy00ZmU1LWE4NjYtZGQ1YmM1ODhlZmE3IiwiaW50ZWdyYXRpb25Vc2VySWQiOiJlNzIwNzcyNy02ZjgyLTQ0NTMtYWQ1Yi00MmYwN2E1NmU1ZWUiLCJhY2NvdW50SWQiOiIxMGU5OWYzMC00OWQ3LTRkOWMtYWIxYS0yZTYyNjExOTZhNGIiLCJyZWZyZXNoVG9rZW5JZCI6Ijg3NmY3MTc2LWZhNjAtNGM0Mi04N2QyLWUxZmVhYzUxN2M4YyIsImludGVncmF0aW9uQXBpS2V5SWQiOiJlMGYzNDViYS1hZGJiLTQ5ZTgtYTY2My1mOTE3MjNhNzQ4ZDEiLCJpYXQiOjE3NTI3NTI0ODcsImV4cCI6MTc1Mjc1NjA4N30.ORvGQTRr5vvXPcTdshTre9g9ufSE7ZlGTdDF42vl7Ho",
        refreshToken:
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbnRlZ3JhdGlvbklkIjoiYjI4MGFlNTEtMmJlMy00ZmU1LWE4NjYtZGQ1YmM1ODhlZmE3IiwiaW50ZWdyYXRpb25Vc2VySWQiOiJlNzIwNzcyNy02ZjgyLTQ0NTMtYWQ1Yi00MmYwN2E1NmU1ZWUiLCJhY2NvdW50SWQiOiIxMGU5OWYzMC00OWQ3LTRkOWMtYWIxYS0yZTYyNjExOTZhNGIiLCJyZWZyZXNoVG9rZW5JZCI6IjIyZTgzMTM4LTI3Y2ItNDllMi1hNmVlLWMxNDAzZmU1M2I5NyIsImludGVncmF0aW9uQXBpS2V5SWQiOiJlMGYzNDViYS1hZGJiLTQ5ZTgtYTY2My1mOTE3MjNhNzQ4ZDEiLCJpYXQiOjE3NTI3NDg0MDQsImV4cCI6MTc1MjgzNDgwNH0.hPg5WIslesFKW6stuWSYsK-7uNPwwfHZ0SBOVjU7S84",
        accessTokenExpiresAtUnixMs: 1_752_749_904_437
    )
}

@main
struct CLI {
    static func main() async {
        do {
            let sdk = await SwiftSDK(authFunction: authFn)
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
