public protocol CategoryImageProtocol {
  var id: String { get }
  var url: String { get }
}

public protocol CategoryProtocol {
  var id: String { get }
  var name: String { get }
  var image: CategoryImageProtocol? { get }
}

public struct Category: CategoryProtocol {
  public let id: String
  public let name: String
  public let image: CategoryImageProtocol?

  public init(id: String, name: String, image: CategoryImageProtocol?) {
    self.id = id
    self.name = name
    self.image = image
  }
}

public struct CategoryImage: CategoryImageProtocol {
  public let id: String
  public let url: String

  public init(id: String, url: String) {
    self.id = id
    self.url = url
  }
}