import CoreGraphics

/// Which logo strip sits in the top of the case.
public enum CaseStyle: String, Sendable, Codable, CaseIterable, Identifiable {
    case switch2
    case switch1
    case plain

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .switch2: "Switch 2"
        case .switch1: "Switch"
        case .plain: "None"
        }
    }

    /// "None" drops the whole strip, so the art fills the icon.
    public var showsBand: Bool { self != .plain }

    /// The style matching a game's platform.
    public init(platform: Platform) {
        self = platform == .switch2 ? .switch2 : .switch1
    }
}

/// How the art sits in the case. `offset` is relative to the art's overflow on each axis
/// (-1 = fully left/up, 1 = fully right/down), so the art always covers the window.
public struct CropSettings: Sendable, Equatable, Codable {
    public static let zoomRange: ClosedRange<CGFloat> = 1...3

    public var zoom: CGFloat {
        didSet { zoom = zoom.clamped(to: Self.zoomRange) }
    }
    public var offset: CGPoint {
        didSet { offset = CGPoint(x: offset.x.clamped(to: -1...1), y: offset.y.clamped(to: -1...1)) }
    }

    public init(zoom: CGFloat = 1, offset: CGPoint = .zero) {
        self.zoom = zoom.clamped(to: Self.zoomRange)
        self.offset = CGPoint(x: offset.x.clamped(to: -1...1), y: offset.y.clamped(to: -1...1))
    }
}

public struct IconOptions: Sendable, Equatable, Codable {
    public var style: CaseStyle
    public var crop: CropSettings
    /// The red spine down the right-hand side.
    public var showsSpine: Bool
    /// Inset the icon on the macOS grid with a drop shadow. Off fills the whole canvas.
    public var macOSGrid: Bool

    public init(
        style: CaseStyle = .switch2,
        crop: CropSettings = .init(),
        showsSpine: Bool = false,
        macOSGrid: Bool = true
    ) {
        self.style = style
        self.crop = crop
        self.showsSpine = showsSpine
        self.macOSGrid = macOSGrid
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
