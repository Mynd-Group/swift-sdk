public protocol CategoryImageProtocol: Sendable {
    var id: String { get }
    var url: String { get }
}

public protocol CategoryProtocol: Sendable {
    var id: String { get }
    var name: String { get }
    var image: CategoryImage? { get }
}

public struct Category: CategoryProtocol, Decodable {
    public let id: String
    public let name: String
    public let image: CategoryImage?

    public init(id: String, name: String, image: CategoryImage?) {
        self.id = id
        self.name = name
        self.image = image
    }
}

public struct CategoryImage: CategoryImageProtocol, Decodable {
    public let id: String
    public let url: String

    public init(id: String, url: String) {
        self.id = id
        self.url = url
    }
}
