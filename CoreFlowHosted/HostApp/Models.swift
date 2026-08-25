import SwiftData

@Model
final class Novel {
    var title: String
    var genre: String
    init(title: String, genre: String) {
        self.title = title
        self.genre = genre
    }
}

@Model
final class Tag {
    var name: String
    init(name: String) {
        self.name = name
    }
}
