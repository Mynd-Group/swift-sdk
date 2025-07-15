public protocol SongHLSProtocol {
    var id: String { get }
    var url: String { get }
    var durationInSeconds: Int { get }
    var urlExpiresAtISO: String { get }
}

public protocol SongMP3Protocol {
    var id: String { get }
    var url: String { get }
    var durationInSeconds: Int { get }
    var urlExpiresAtISO: String { get }
}

public protocol SongImageProtocol {
    var id: String { get }
    var url: String { get }
}

public protocol AudioProtocol {
    var hls: SongHLS { get }
    var mp3: SongMP3 { get }
}

public protocol ArtistProtocol {
    var id: String { get }
    var name: String { get }
}

public protocol SongProtocol {
    var id: String { get }
    var name: String { get }
    var image: SongImage? { get }
    var audio: Audio { get }
    var artists: [Artist] { get }
}

public struct Song: SongProtocol, Decodable {
    public let id: String
    public let name: String
    public let image: SongImage?
    public let audio: Audio
    public let artists: [Artist]

    public init(id: String, name: String, image: SongImage?, audio: Audio, artists: [Artist]) {
        self.id = id
        self.name = name
        self.image = image
        self.audio = audio
        self.artists = artists
    }
}

public struct SongImage: SongImageProtocol, Decodable {
    public let id: String
    public let url: String

    public init(id: String, url: String) {
        self.id = id
        self.url = url
    }
}

public struct Artist: ArtistProtocol, Decodable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct SongHLS: SongHLSProtocol, Decodable {
    public let id: String
    public let url: String
    public let durationInSeconds: Int
    public let urlExpiresAtISO: String

    public init(id: String, url: String, durationInSeconds: Int, urlExpiresAtISO: String) {
        self.id = id
        self.url = url
        self.durationInSeconds = durationInSeconds
        self.urlExpiresAtISO = urlExpiresAtISO
    }
}

public struct SongMP3: SongMP3Protocol, Decodable {
    public let id: String
    public let url: String
    public let durationInSeconds: Int
    public let urlExpiresAtISO: String

    public init(id: String, url: String, durationInSeconds: Int, urlExpiresAtISO: String) {
        self.id = id
        self.url = url
        self.durationInSeconds = durationInSeconds
        self.urlExpiresAtISO = urlExpiresAtISO
    }
}

public struct Audio: AudioProtocol, Decodable {
    public let hls: SongHLS
    public let mp3: SongMP3

    public init(hls: SongHLS, mp3: SongMP3) {
        self.hls = hls
        self.mp3 = mp3
    }
}

