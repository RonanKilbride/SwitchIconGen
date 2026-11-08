import CoreGraphics
import Foundation
import ImageIO

/// Downloads and decodes images. Decoded images are cached in memory, bytes on disk via
/// `URLCache`, and concurrent requests for the same image share one download.
public actor ImageLoader {
    public static let shared = ImageLoader()

    private struct Key: Hashable { let url: URL; let maxPixelSize: Int? }

    private let session: URLSession
    private var cache: [Key: CGImage] = [:]
    private var cacheOrder: [Key] = []
    private let cacheLimit = 200
    private var inFlight: [Key: Task<CGImage, Error>] = [:]

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 200 << 20)
            config.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: config)
        }
    }

    /// - Parameter maxPixelSize: decode a downsampled thumbnail instead of the full image.
    public func image(at url: URL, maxPixelSize: Int? = nil) async throws -> CGImage {
        let key = Key(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return try await task.value }

        let session = session
        let task = Task<CGImage, Error> {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (body, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw ArtworkError.badResponse(status: http.statusCode)
                }
                data = body
            }
            return try Self.decode(data, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let image = try await task.value
        store(image, for: key)
        return image
    }

    private func store(_ image: CGImage, for key: Key) {
        cache[key] = image
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    public static func decode(_ data: Data, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw ArtworkError.notAnImage }

        // The thumbnail API applies EXIF orientation; with no size cap it decodes at full size.
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let maxPixelSize { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ArtworkError.notAnImage
        }
        return image
    }
}
