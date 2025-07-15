import Foundation

public protocol PlaylistImageProtocol: Sendable {
    var id: String { get }
    var url: String { get }
}

public protocol PlaylistProtocol: Sendable {
    var id: String { get }
    var name: String { get }
    var image: PlaylistImage? { get }
    var description: String? { get }
    var instrumentation: String? { get }
    var genre: String? { get }
    var bpm: Int? { get }
}

public struct PlaylistImage: PlaylistImageProtocol, Decodable, Sendable {
    public let id: String
    public let url: String

    public init(id: String, url: String) {
        self.id = id
        self.url = url
    }
}

public struct Playlist: PlaylistProtocol, Decodable, Sendable {
    public let id: String
    public let name: String
    public let image: PlaylistImage?
    public let description: String?
    public let instrumentation: String?
    public let genre: String?
    public let bpm: Int?

    public init(id: String, name: String, image: PlaylistImage?, description: String?, instrumentation: String?, genre: String?, bpm: Int?) {
        self.id = id
        self.name = name
        self.image = image
        self.description = description
        self.instrumentation = instrumentation
        self.genre = genre
        self.bpm = bpm
    }
}
