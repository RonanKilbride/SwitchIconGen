import CoreGraphics

/// Case geometry in a 1024×1024 design space (y-down), and placement on the macOS icon grid.
public enum CaseLayout {
    public static let designSize: CGFloat = 1024

    /// A logo band across the top and an optional spine down the right.
    static let bandHeight: CGFloat = 136
    static let spineWidth: CGFloat = 36

    /// Where the art shows: below the band, left of the spine.
    public static func artWindow(showsSpine: Bool, showsBand: Bool) -> CGRect {
        let fill = artFillArea(showsBand: showsBand)
        return CGRect(x: 0, y: fill.minY, width: designSize - (showsSpine ? spineWidth : 0), height: fill.height)
    }

    /// The area the art is sized and centred against. It ignores the spine, which overlaps
    /// it, so toggling the spine doesn't move the art.
    public static func artFillArea(showsBand: Bool) -> CGRect {
        let top = showsBand ? bandHeight : 0
        return CGRect(x: 0, y: top, width: designSize, height: designSize - top)
    }

    /// The spine, starting below the band.
    public static func spine(showsBand: Bool) -> CGRect {
        let fill = artFillArea(showsBand: showsBand)
        return CGRect(x: designSize - spineWidth, y: fill.minY, width: spineWidth, height: fill.height)
    }

    /// The logo band across the top of the case.
    public static let topBand = CGRect(x: 0, y: 0, width: designSize, height: bandHeight)

    /// Side of the app's preview, in points. Logo offsets are tuned against it.
    static let referencePreviewSide: CGFloat = 336

    /// Design units per preview point (the design maps onto the icon body, inside the margin).
    static var designUnitsPerPreviewPoint: CGFloat {
        designSize / (referencePreviewSide * (1 - 2 * gridInsetFraction))
    }

    /// How far below the band's centre the logo sits, in preview points.
    static let logoDropInPreviewPoints: CGFloat = 1.0

    /// `logoDropInPreviewPoints` in design units.
    public static var logoDrop: CGFloat { logoDropInPreviewPoints * designUnitsPerPreviewPoint }

    /// Where to draw a logo image (design units) so the logo is centred in the band.
    public static func brandingRect(for layer: CaseAssets.Layer) -> CGRect {
        let bounds = layer.logoBounds
        let scale = topBand.height * layer.heightInBand / bounds.height
        let target = CGPoint(x: designSize / 2, y: topBand.midY + logoDrop)
        return CGRect(
            x: target.x - bounds.midX * scale,
            y: target.y - bounds.midY * scale,
            width: layer.canvasSize.width * scale,
            height: layer.canvasSize.height * scale
        )
    }

    /// macOS icon grid: an 824pt body centred in the 1024pt canvas.
    public static let gridInsetFraction: CGFloat = 100 / 1024

    /// Continuous corner radius of the icon body, as a fraction of its side.
    public static let cornerRadiusFraction: CGFloat = 0.2237

    /// The case red.
    public static let caseRed = CGColor(srgbRed: 230 / 255, green: 0, blue: 18 / 255, alpha: 1)

    /// Where the art is drawn (design units): aspect-fill, then zoom, then pan within the
    /// overflow, so it always covers the fill area.
    public static func artRect(artSize: CGSize, crop: CropSettings, showsBand: Bool) -> CGRect {
        let window = artFillArea(showsBand: showsBand)
        guard artSize.width > 0, artSize.height > 0 else { return window }

        let scale = max(window.width / artSize.width, window.height / artSize.height) * crop.zoom
        let size = CGSize(width: artSize.width * scale, height: artSize.height * scale)
        let overflow = panRange(drawnSize: size, in: window)
        let center = CGPoint(
            x: window.midX + crop.offset.x * overflow.width,
            y: window.midY + crop.offset.y * overflow.height
        )
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// How far (design units) the art can move each way from centre before exposing an edge.
    public static func panRange(artSize: CGSize, crop: CropSettings, showsBand: Bool) -> CGSize {
        let window = artFillArea(showsBand: showsBand)
        guard artSize.width > 0, artSize.height > 0 else { return .zero }
        let scale = max(window.width / artSize.width, window.height / artSize.height) * crop.zoom
        return panRange(drawnSize: CGSize(width: artSize.width * scale, height: artSize.height * scale), in: window)
    }

    private static func panRange(drawnSize: CGSize, in window: CGRect) -> CGSize {
        CGSize(
            width: max(0, (drawnSize.width - window.width) / 2),
            height: max(0, (drawnSize.height - window.height) / 2)
        )
    }

    /// The icon body (pixels, y-up) within a square canvas.
    public static func bodyRect(canvas: CGFloat, onGrid: Bool) -> CGRect {
        let inset = onGrid ? (canvas * gridInsetFraction).rounded() : 0
        return CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    }

    /// Converts a design-space rect (y-down) to pixel space (y-up) inside `body`.
    public static func map(_ rect: CGRect, into body: CGRect) -> CGRect {
        let k = body.width / designSize
        return CGRect(
            x: body.minX + rect.minX * k,
            y: body.minY + (designSize - rect.maxY) * k,
            width: rect.width * k,
            height: rect.height * k
        )
    }
}
