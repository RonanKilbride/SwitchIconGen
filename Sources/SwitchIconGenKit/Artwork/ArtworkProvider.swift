import Foundation

/// Consoles we search for. Raw values are the store's platform codes.
public enum Platform: String, Sendable, Hashable, CaseIterable {
    case switch1 = "HAC"
    case switch2 = "BEE"

    public var displayName: String {
        switch self {
        case .switch1: "Switch"
        case .switch2: "Switch 2"
        }
    }
}

/// A search result: a game and its square key art.
public struct GameArtwork: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let platforms: Set<Platform>
    public let imageURL: URL
    public let releaseDate: String?

    public init(id: String, title: String, platforms: Set<Platform>, imageURL: URL, releaseDate: String? = nil) {
        self.id = id
        self.title = title
        self.platforms = platforms
        self.imageURL = imageURL
        self.releaseDate = releaseDate
    }

    /// The release year, from the index's "dd/MM/yyyy" date.
    public var releaseYear: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        let year = String(releaseDate.suffix(4))
        return year.allSatisfy(\.isNumber) ? year : nil
    }

    /// Newest platform first, so "Switch 2 Edition" titles read as Switch 2.
    public var primaryPlatform: Platform {
        platforms.contains(.switch2) ? .switch2 : .switch1
    }
}

public protocol ArtworkProvider: Sendable {
    func search(_ query: String, limit: Int) async throws -> [GameArtwork]
}

public enum ArtworkError: LocalizedError, Equatable {
    case badResponse(status: Int)
    case notAnImage
    case unreadableFile

    public var errorDescription: String? {
        switch self {
        case .badResponse(let status): "The server responded with HTTP \(status)."
        case .notAnImage: "The download wasn't an image."
        case .unreadableFile: "That file couldn't be read as an image."
        }
    }
}
