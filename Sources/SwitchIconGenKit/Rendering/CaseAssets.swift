import AppKit
import os

/// The bundled logo images, rasterised on demand and cached per pixel size. The case itself
/// is drawn in `IconComposer`.
public final class CaseAssets: Sendable {
    public enum Layer: String, Sendable, CaseIterable {
        case brandingSwitch2 = "branding_switch2"
        case brandingSwitch = "branding_switch"

        /// The source image's size. Logos are white on transparent.
        public var canvasSize: CGSize {
            switch self {
            case .brandingSwitch2: CGSize(width: 150, height: 136)
            case .brandingSwitch: CGSize(width: 128, height: 138)
            }
        }

        /// Where the visible logo sits inside the source image.
        public var logoBounds: CGRect {
            switch self {
            case .brandingSwitch2: CGRect(x: 3, y: 3, width: 144, height: 130)
            case .brandingSwitch: CGRect(x: 3, y: 3, width: 122, height: 132)
            }
        }

        /// Logo height as a fraction of the band height.
        public var heightInBand: CGFloat {
            switch self {
            case .brandingSwitch2: 130.0 / 190.0
            case .brandingSwitch: 132.0 / 190.0
            }
        }
    }

    public static let bundled = CaseAssets()

    private struct Key: Hashable { let layer: Layer; let width: Int; let height: Int }

    private let state = OSAllocatedUnfairLock<[Key: CGImage]>(initialState: [:])
    private let sources: [Layer: Data]

    public convenience init() {
        self.init(bundle: .module)
    }

    public init(bundle: Bundle) {
        var sources: [Layer: Data] = [:]
        for layer in Layer.allCases {
            guard let url = bundle.url(forResource: layer.rawValue, withExtension: "png", subdirectory: "Resources")
                ?? bundle.url(forResource: layer.rawValue, withExtension: "png"),
                let data = try? Data(contentsOf: url)
            else {
                assertionFailure("Missing bundled asset \(layer.rawValue).png")
                continue
            }
            sources[layer] = data
        }
        self.sources = sources
    }

    public func layers(for style: CaseStyle) -> [Layer] {
        switch style {
        case .switch2: [.brandingSwitch2]
        case .switch1: [.brandingSwitch]
        case .plain: []
        }
    }

    /// The layer's whole canvas rasterised at `width`×`height` pixels (transparent where empty).
    public func image(_ layer: Layer, width: Int, height: Int) -> CGImage? {
        let key = Key(layer: layer, width: width, height: height)
        return state.withLock { cache in
            if let cached = cache[key] { return cached }
            guard let data = sources[layer], let rendered = Self.rasterize(data, width: width, height: height) else { return nil }
            cache[key] = rendered
            return rendered
        }
    }

    private static func rasterize(_ data: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let image = NSImage(data: data),
              let context = CGContext.canvas(width: width, height: height)
        else { return nil }

        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

extension CGContext {
    /// Premultiplied RGBA in sRGB.
    static func squareCanvas(pixels: Int) -> CGContext? {
        canvas(width: pixels, height: pixels)
    }

    static func canvas(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
