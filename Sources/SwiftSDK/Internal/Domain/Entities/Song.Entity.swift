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
  var hls: SongHLSProtocol { get }
  var mp3: SongMP3Protocol { get }
}

public protocol ArtistProtocol {
  var id: String { get }
  var name: String { get }
}

public protocol SongProtocol {
  var id: String { get }
  var name: String { get }
  var image: SongImageProtocol? { get }
  var audio: AudioProtocol { get }
  var artists: [ArtistProtocol] { get }
}

public struct Song: SongProtocol {
  public let id: String
  public let name: String
  public let image: SongImageProtocol?
  public let audio: AudioProtocol
  public let artists: [ArtistProtocol]

  public init(id: String, name: String, image: SongImageProtocol?, audio: AudioProtocol, artists: [ArtistProtocol]) {
    self.id = id
    self.name = name
    self.image = image
    self.audio = audio
    self.artists = artists
  }
}

public struct SongImage: SongImageProtocol {
  public let id: String
  public let url: String

  public init(id: String, url: String) {
    self.id = id
    self.url = url
  }
}

public struct Artist: ArtistProtocol {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct SongHLS: SongHLSProtocol {
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

public struct SongMP3: SongMP3Protocol {
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

public struct Audio: AudioProtocol {
  public let hls: SongHLSProtocol
  public let mp3: SongMP3Protocol

  public init(hls: SongHLSProtocol, mp3: SongMP3Protocol) {
    self.hls = hls
    self.mp3 = mp3
  }
}