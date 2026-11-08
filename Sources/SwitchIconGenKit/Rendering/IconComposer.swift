import CoreGraphics
import SwiftUI

/// Composites art into the case on the macOS icon grid. Pure CoreGraphics, so it is
/// thread-safe and deterministic.
public struct IconComposer: Sendable {
    public enum RenderError: Error { case contextUnavailable }

    private let assets: CaseAssets

    public init(assets: CaseAssets = .bundled) {
        self.assets = assets
    }

    /// - Parameters:
    ///   - art: the artwork, or `nil` for an empty case.
    ///   - pixels: output side length.
    public func render(art: CGImage?, options: IconOptions, pixels: Int = 1024) throws -> CGImage {
        guard let ctx = CGContext.squareCanvas(pixels: pixels) else { throw RenderError.contextUnavailable }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)

        let canvas = CGFloat(pixels)
        let body = CaseLayout.bodyRect(canvas: canvas, onGrid: options.macOSGrid)
        let shape = Self.squircle(in: body)
        let draw = DesignSpace(ctx: ctx, body: body)

        let showsBand = options.style.showsBand

        if options.macOSGrid {
            drawShadow(shape, in: ctx, canvas: canvas, showsBand: showsBand)
        }

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()

        drawArt(art, crop: options.crop, showsBand: showsBand, draw)
        if options.showsSpine {
            drawSpine(showsBand: showsBand, draw)
        }
        if showsBand {
            drawBand(draw)
        }

        // Rasterised at the drawn size so small icons stay crisp.
        for layer in assets.layers(for: options.style) {
            let rect = draw.rect(CaseLayout.brandingRect(for: layer))
            let width = Int(rect.width.rounded()), height = Int(rect.height.rounded())
            if let image = assets.image(layer, width: width, height: height) {
                ctx.draw(image, in: rect)
            }
        }

        ctx.restoreGState()

        guard let image = ctx.makeImage() else { throw RenderError.contextUnavailable }
        return image
    }

    // MARK: - Layers

    private func drawShadow(_ shape: CGPath, in ctx: CGContext, canvas: CGFloat, showsBand: Bool) {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -canvas * 0.01),
            blur: canvas * 0.024,
            color: CGColor(gray: 0, alpha: 0.3)
        )
        ctx.addPath(shape)
        // Same colour as the edge on top, so antialiasing doesn't leave a fringe.
        ctx.setFillColor(showsBand ? CaseLayout.caseRed : CGColor(gray: 0.13, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawArt(_ art: CGImage?, crop: CropSettings, showsBand: Bool, _ draw: DesignSpace) {
        // Bleed 2 units under the band so the join never shows a seam.
        let fill = CaseLayout.artFillArea(showsBand: showsBand)
        let bleed = showsBand
            ? CGRect(x: fill.minX, y: fill.minY - 2, width: fill.width, height: fill.height + 2)
            : fill

        draw.ctx.saveGState()
        draw.ctx.clip(to: draw.rect(bleed))
        draw.ctx.setFillColor(CGColor(gray: 0.13, alpha: 1))
        draw.ctx.fill(draw.rect(bleed))
        if let art {
            let size = CGSize(width: art.width, height: art.height)
            draw.ctx.draw(art, in: draw.rect(CaseLayout.artRect(artSize: size, crop: crop, showsBand: showsBand)))
        }
        draw.ctx.restoreGState()
    }

    /// The spine down the right-hand side; the icon outline clips its outer edge.
    private func drawSpine(showsBand: Bool, _ draw: DesignSpace) {
        let ctx = draw.ctx
        let k = draw.body.width / CaseLayout.designSize
        let spineArea = CaseLayout.spine(showsBand: showsBand)
        let spine = draw.rect(spineArea)

        // Base fill with a soft shadow onto the art.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: -2 * k, height: 0), blur: 12 * k, color: Palette.black(0.3))
        ctx.setFillColor(Palette.red)
        ctx.fill(spine)
        ctx.restoreGState()

        // Darker toward the outer edge.
        draw.linearGradient(
            in: spineArea,
            from: CGPoint(x: spineArea.minX, y: 0), to: CGPoint(x: spineArea.maxX, y: 0),
            colors: [Palette.red, Palette.redShade]
        )
        // Highlight along the inner edge.
        draw.fill(CGRect(x: spineArea.minX, y: spineArea.minY, width: 2, height: spineArea.height), Palette.white(0.16))
    }

    /// The red band, lit slightly from above, with a contact shadow onto the art below.
    private func drawBand(_ draw: DesignSpace) {
        let band = CaseLayout.topBand
        draw.linearGradient(
            in: CGRect(x: 0, y: band.maxY, width: CaseLayout.designSize, height: 14),
            from: CGPoint(x: 0, y: band.maxY), to: CGPoint(x: 0, y: band.maxY + 14),
            colors: [Palette.black(0.22), Palette.black(0)]
        )
        draw.linearGradient(
            in: band,
            from: CGPoint(x: 0, y: band.minY), to: CGPoint(x: 0, y: band.maxY),
            colors: [Palette.redLight, Palette.red]
        )
    }

    /// Apple's continuous-corner ("squircle") icon shape.
    static func squircle(in rect: CGRect) -> CGPath {
        RoundedRectangle(cornerRadius: rect.width * CaseLayout.cornerRadiusFraction, style: .continuous)
            .path(in: rect)
            .cgPath
    }
}

private enum Palette {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    static let red = CaseLayout.caseRed
    static let redLight = CGColor(srgbRed: 0.95, green: 0.08, blue: 0.13, alpha: 1)
    static let redShade = CGColor(srgbRed: 0.80, green: 0.0, blue: 0.06, alpha: 1)
    static func white(_ alpha: CGFloat) -> CGColor { CGColor(gray: 1, alpha: alpha) }
    static func black(_ alpha: CGFloat) -> CGColor { CGColor(gray: 0, alpha: alpha) }
}

/// Draws in design space (1024 units, y-down), mapped into the icon body.
private struct DesignSpace {
    let ctx: CGContext
    let body: CGRect

    func rect(_ r: CGRect) -> CGRect { CaseLayout.map(r, into: body) }

    func point(_ p: CGPoint) -> CGPoint {
        let k = body.width / CaseLayout.designSize
        return CGPoint(x: body.minX + p.x * k, y: body.minY + (CaseLayout.designSize - p.y) * k)
    }

    func fill(_ r: CGRect, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(rect(r))
    }

    func linearGradient(in r: CGRect, from: CGPoint, to: CGPoint, colors: [CGColor], locations: [CGFloat]? = nil) {
        guard let gradient = CGGradient(colorsSpace: Palette.space, colors: colors as CFArray, locations: locations) else { return }
        ctx.saveGState()
        ctx.clip(to: rect(r))
        ctx.drawLinearGradient(
            gradient, start: point(from), end: point(to),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }
}
