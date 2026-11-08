import Foundation

/// Searches the public European eShop index (a Solr endpoint). No API key; returns square
/// 500px key art for Switch and Switch 2 titles.
public struct EShopProvider: ArtworkProvider {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://searching.nintendo-europe.com/en/select")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func search(_ query: String, limit: Int = 30) async throws -> [GameArtwork] {
        guard let url = requestURL(for: query, limit: limit) else { return [] }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ArtworkError.badResponse(status: http.statusCode)
        }
        return try Self.parse(data)
    }

    /// `nil` when the query has no searchable words.
    func requestURL(for query: String, limit: Int) -> URL? {
        guard let q = Self.solrQuery(query) else { return nil }
        let platforms = Platform.allCases.map(\.rawValue).joined(separator: " OR ")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fq", value: "type:GAME AND playable_on_txt:(\(platforms))"),
            URLQueryItem(name: "fl", value: "fs_id,title,image_url_sq_s,image_url,playable_on_txt,pretty_date_s"),
            URLQueryItem(name: "rows", value: String(limit)),
            URLQueryItem(name: "wt", value: "json"),
        ]
        return components.url!
    }

    /// Every word must match, and the last one may be a prefix, so "ocar" finds Ocarina of
    /// Time while typing and "mario kart" doesn't list every Mario game. Only letters and
    /// digits are kept, which also keeps Solr syntax out of the query.
    static func solrQuery(_ text: String) -> String? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard let last = words.last else { return nil }
        // The exact term keeps relevance ranking; a bare wildcard would score every hit the same.
        return (words.dropLast().map { "+\($0)" } + ["+(\(last) OR \(last)*)"]).joined(separator: " ")
    }

    static func parse(_ data: Data) throws -> [GameArtwork] {
        let payload = try JSONDecoder().decode(SolrResponse.self, from: data)
        var seenImages = Set<URL>()
        return payload.response.docs.compactMap { doc in
            guard
                let title = doc.title,
                let url = (doc.image_url_sq_s ?? doc.image_url).flatMap(normalizedURL),
                seenImages.insert(url).inserted
            else { return nil }
            let platforms = Set((doc.playable_on_txt ?? []).compactMap { Platform(rawValue: $0.uppercased()) })
            guard !platforms.isEmpty else { return nil }
            return GameArtwork(
                id: doc.fs_id ?? url.absoluteString,
                title: title,
                platforms: platforms,
                imageURL: url,
                releaseDate: doc.pretty_date_s
            )
        }
    }

    /// The index mixes `https://`, `http://` and protocol-relative `//` URLs.
    static func normalizedURL(_ raw: String) -> URL? {
        var string = raw.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("//") { string = "https:" + string }
        if string.hasPrefix("http://") { string = "https://" + string.dropFirst("http://".count) }
        return URL(string: string)
    }
}

private struct SolrResponse: Decodable {
    struct Body: Decodable { let docs: [Doc] }
    struct Doc: Decodable {
        let fs_id: String?
        let title: String?
        let image_url_sq_s: String?
        let image_url: String?
        let playable_on_txt: [String]?
        let pretty_date_s: String?
    }
    let response: Body
}
