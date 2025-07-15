import SwiftSDK

public func authFn() async -> AuthPayload {
    return AuthPayload(
        accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbnRlZ3JhdGlvbklkIjoiZWNjNzU2NzgtNWQ3Yy00NzJkLTgwMDMtNGUxZWM1YzE2MDdiIiwiaW50ZWdyYXRpb25Vc2VySWQiOiI4MTY1NmI5Ni1iN2E3LTQ0NGQtOTkyNy0yMGIyYzNkN2M2NmEiLCJhY2NvdW50SWQiOiJjYWEzMGUxYS1mZTFiLTRjMzQtODJiMy0zMDFlNzI0YzU2NDIiLCJyZWZyZXNoVG9rZW5JZCI6IjA3MzhmNDM0LTQxZTgtNGJkNC04YjYwLWQ0NWIxNjAyYTgxOSIsImludGVncmF0aW9uQXBpS2V5SWQiOiJiYzEwMzAxNS03M2FlLTRmMGEtYmM0OC1kYjE5ZTg0MjQwMTciLCJpYXQiOjE3NTI1OTMyNzUsImV4cCI6MTc1MjU5NTA3NX0.k4gpCYbXC1DxNHqwCiBs7cFV8UCw81tVOREmcigCY84", refreshToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpbnRlZ3JhdGlvbklkIjoiZWNjNzU2NzgtNWQ3Yy00NzJkLTgwMDMtNGUxZWM1YzE2MDdiIiwiaW50ZWdyYXRpb25Vc2VySWQiOiI4MTY1NmI5Ni1iN2E3LTQ0NGQtOTkyNy0yMGIyYzNkN2M2NmEiLCJhY2NvdW50SWQiOiJjYWEzMGUxYS1mZTFiLTRjMzQtODJiMy0zMDFlNzI0YzU2NDIiLCJyZWZyZXNoVG9rZW5JZCI6IjA3MzhmNDM0LTQxZTgtNGJkNC04YjYwLWQ0NWIxNjAyYTgxOSIsImludGVncmF0aW9uQXBpS2V5SWQiOiJiYzEwMzAxNS03M2FlLTRmMGEtYmM0OC1kYjE5ZTg0MjQwMTciLCJpYXQiOjE3NTI1OTMyNzUsImV4cCI6MTc1MjY3OTY3NX0.z-5n2tPfVyZhaln4j7T8lfypySiXP1AP41AuDKiS8fY", accessTokenExpiresAtUnixMs: 1_752_594_775_627
    )
}

@main
struct CLI {
    static func main() async {
        do {
            let sdk = SwiftSDK(authFunction: authFn)
            let categories = try await sdk.catalogue.getCategories()
            print("Categories: \(categories.map { $0.name })")
        } catch {
            print("Error: \(error)")
        }
    }
}
