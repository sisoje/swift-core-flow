import SwiftData

@Model
public final class Book {
    public var title: String
    public var author: String
    public var isFavorite: Bool = false

    public init(title: String, author: String, isFavorite: Bool = false) {
        self.title = title
        self.author = author
        self.isFavorite = isFavorite
    }
}
