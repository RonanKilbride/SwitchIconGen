import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Writes icons as PNG and ICNS. Each size is rendered natively, not downscaled, so the
/// logo stays legible at small sizes.
public struct IconExporter: Sendable {
    /// Pixel sizes an ICNS needs to cover 16pt…512pt at 1x and 2x.
    public static let icnsPixelSizes = [16, 32, 64, 128, 256, 512, 1024]

    public enum ExportError: LocalizedError {
        case cannotCreateFile
        case writeFailed

        public var errorDescription: String? {
            switch self {
            case .cannotCreateFile: "Couldn't create the output file."
            case .writeFailed: "Couldn't write the image data."
            }
        }
    }

    private let composer: IconComposer

    public init(composer: IconComposer = IconComposer()) {
        self.composer = composer
    }

    public func writePNG(art: CGImage?, options: IconOptions, to url: URL, pixels: Int = 1024) throws {
        let image = try composer.render(art: art, options: options, pixels: pixels)
        try write([image], type: .png, to: url)
    }

    public func writeICNS(art: CGImage?, options: IconOptions, to url: URL) throws {
        let images = try Self.icnsPixelSizes.map { try composer.render(art: art, options: options, pixels: $0) }
        try write(images, type: .icns, to: url)
    }

    /// A multi-representation image suitable for `NSWorkspace.setIcon` and the pasteboard.
    public func makeNSImage(art: CGImage?, options: IconOptions) throws -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        for pixels in Self.icnsPixelSizes {
            let rep = NSBitmapImageRep(cgImage: try composer.render(art: art, options: options, pixels: pixels))
            // 1024px is 512pt @2x; other sizes are 1x.
            let points = pixels == 1024 ? 512 : pixels
            rep.size = NSSize(width: points, height: points)
            image.addRepresentation(rep)
        }
        return image
    }

    private func write(_ images: [CGImage], type: UTType, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, images.count, nil
        ) else { throw ExportError.cannotCreateFile }
        for image in images {
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw ExportError.writeFailed }
    }
}
