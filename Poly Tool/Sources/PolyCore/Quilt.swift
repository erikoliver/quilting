import Foundation
import CoreGraphics

public enum PieceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case triangle, diamond, trapezoid, parallelogram, hexagon, jewel, sideTriangle, sideSettingTriangle
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .sideTriangle: return "Side triangle"
        case .sideSettingTriangle: return "120° side triangle"
        default: return rawValue.capitalized
        }
    }
    public var detail: String {
        switch self {
        case .triangle: return "60° equilateral"
        case .diamond: return "60° diamond"
        case .trapezoid: return "Half hexagon"
        case .parallelogram: return "60° · 2:1 sides"
        case .hexagon: return "Regular · flat to flat"
        case .jewel: return "Dahlia petal · clipped diamond"
        case .sideTriangle: return "30°–60°–90° · half triangle"
        case .sideSettingTriangle: return "120° wide triangle"
        }
    }
    /// Area in triangles of the same nominal height, not a decomposition count.
    public var triangleCount: Double {
        switch self {
        case .triangle: return 1
        case .diamond: return 2
        case .trapezoid, .sideSettingTriangle: return 3
        case .parallelogram: return 4
        case .hexagon: return 1.5
        case .jewel: return 1.75
        case .sideTriangle: return 0.5
        }
    }
    public var vertices: [GridPoint] {
        switch self {
        case .triangle: return [.init(0, 0), .init(1, 0), .init(0, 1)]
        case .diamond: return [.init(0, 0), .init(1, 0), .init(1, 1), .init(0, 1)]
        case .trapezoid: return [.init(0, 0), .init(2, 0), .init(1, 1), .init(0, 1)]
        case .parallelogram: return [.init(0, 0), .init(2, 0), .init(2, 1), .init(0, 1)]
        // A hexagon's size is its full flat-to-flat height, not its component triangle height.
        case .hexagon: return [.init(0, 0), .init(0.5, 0), .init(0.5, 0.5), .init(0, 1), .init(-0.5, 1), .init(-0.5, 0.5)]
        // Equal short edges meet at 120°. Size is the altitude to the long base.
        case .sideSettingTriangle: return [.init(0, 0), .init(1, 1), .init(-2, 1)]
        // Dancing Dahlias, page 4: retain the diamond except for one half-size tip triangle.
        // Size follows the parent diamond's strip height, so a jewel pairs with that diamond.
        case .jewel: return [.init(0, 0), .init(1, 0), .init(1, 0.5), .init(0.5, 1), .init(0, 1)]
        // Mirror-image straight-edge fillers, as in Dancing Dahlias, page 9.
        case .sideTriangle: return [.init(0, 0), .init(0.5, 0), .init(0, 1)]
        }
    }
}

/// Axial coordinates on an equilateral lattice. One row is one nominal finished inch high.
public struct GridPoint: Codable, Equatable, Hashable, Sendable {
    public var q: Double
    public var r: Double
    public init(_ q: Double, _ r: Double) { self.q = q; self.r = r }
    public var inches: CGPoint { CGPoint(x: (Double(q) + Double(r) / 2) * 2 / sqrt(3), y: Double(r)) }
    public func rotated(_ steps: Int) -> Self {
        var p = self
        for _ in 0..<((steps % 6 + 6) % 6) { p = .init(-p.r, p.q + p.r) }
        return p
    }
    /// Reflect across the vertical line through the rotation anchor.
    public var reflected: Self { .init(-q - r, r) }
    public static func nearest(to inches: CGPoint) -> Self {
        let r = inches.y, q = inches.x * sqrt(3) / 2 - r / 2
        let qi = Int((q * 4).rounded()), ri = Int((r * 4).rounded())
        var best = GridPoint(Double(qi) / 4, Double(ri) / 4), distance = Double.infinity
        for a in (qi - 1)...(qi + 1) { for b in (ri - 1)...(ri + 1) {
            let p = GridPoint(Double(a) / 4, Double(b) / 4), xy = p.inches
            let d = pow(xy.x - inches.x, 2) + pow(xy.y - inches.y, 2)
            if d < distance { best = p; distance = d }
        }}
        return best
    }
}

public struct Fabric: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var hex: String
    public init(id: UUID = UUID(), name: String, hex: String) { self.id = id; self.name = name; self.hex = hex }
    public static let defaults: [Fabric] = [
        Fabric(name: "Juniper", hex: "315D55"), Fabric(name: "Sea Glass", hex: "88B5A5"),
        Fabric(name: "Linen", hex: "EEE3CB"), Fabric(name: "Marigold", hex: "DEA94B"),
        Fabric(name: "Clay", hex: "C76F52"), Fabric(name: "Rose", hex: "C993A1"),
        Fabric(name: "Indigo", hex: "43516F"), Fabric(name: "Ink", hex: "30383C")
    ]
}

public struct Piece: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: PieceKind
    public var size: Double
    public var origin: GridPoint
    public var rotation: Int
    public var fabricID: UUID
    public var flipped: Bool
    public init(id: UUID = UUID(), kind: PieceKind, size: Double = 2, origin: GridPoint = .init(0, 0), rotation: Int = 0, fabricID: UUID, flipped: Bool = false) {
        self.id = id; self.kind = kind; self.size = size; self.origin = origin; self.rotation = rotation; self.fabricID = fabricID; self.flipped = flipped
    }
    private enum CodingKeys: String, CodingKey { case id, kind, size, origin, rotation, fabricID, flipped }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        size = try c.decode(Double.self, forKey: .size)
        origin = try c.decode(GridPoint.self, forKey: .origin)
        rotation = try c.decode(Int.self, forKey: .rotation)
        fabricID = try c.decode(UUID.self, forKey: .fabricID)
        flipped = try c.decodeIfPresent(Bool.self, forKey: .flipped) ?? false
        kind = try c.decode(PieceKind.self, forKey: .kind)
    }
    public var vertices: [CGPoint] {

        kind.vertices.map { v in
            let local = flipped ? v.reflected : v
            let p = GridPoint(local.q * size, local.r * size).rotated(rotation)
            return GridPoint(p.q + origin.q, p.r + origin.r).inches
        }
    }
    public var area: Double { Double(kind.triangleCount) * size * size / sqrt(3) }
    public var nominalStrip: Double { Double(size) + 0.5 }
    public var bounds: CGRect { Geometry.bounds(vertices) }
}

public enum Geometry {
    public static func bounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    /// Separating-axis test. Shared seams and shared tips are allowed.
    public static func overlaps(_ a: Piece, _ b: Piece) -> Bool {
        let av = a.vertices, bv = b.vertices
        for polygon in [av, bv] {
            for i in polygon.indices {
                let p = polygon[i], n = polygon[(i + 1) % polygon.count]
                let axis = CGPoint(x: -(n.y - p.y), y: n.x - p.x)
                let ap = av.map { $0.x * axis.x + $0.y * axis.y }
                let bp = bv.map { $0.x * axis.x + $0.y * axis.y }
                if ap.max()! <= bp.min()! + 1e-8 || bp.max()! <= ap.min()! + 1e-8 { return false }
            }
        }
        return true
    }
}

public struct SummaryRow: Identifiable {
    public var id: String { "\(fabric.id)-\(kind.rawValue)-\(size)" }
    public var fabric: Fabric
    public var kind: PieceKind
    public var size: Double
    public var count: Int
}

public struct Quilt: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var title = "Untitled Quilt"
    public var units = "inches"
    public var sizeConvention = "nominal finished triangle height; strip planning width = height + 0.5 inches"
    public var fabrics: [Fabric] = Fabric.defaults
    public var pieces: [Piece] = []
    public init() {}
    public var bounds: CGRect { Geometry.bounds(pieces.flatMap(\.vertices)) }
    public var area: Double { pieces.reduce(0) { $0 + $1.area } }
    public var triangleUnits: Double { pieces.reduce(0) { $0 + Double($1.kind.triangleCount) * $1.size * $1.size } }
    public func canPlace(_ piece: Piece) -> Bool { !pieces.contains { $0.id != piece.id && Geometry.overlaps($0, piece) } }
    public func fabric(for piece: Piece) -> Fabric { fabrics.first { $0.id == piece.fabricID } ?? fabrics[0] }
    public var summary: [SummaryRow] {
        fabrics.flatMap { fabric in PieceKind.allCases.flatMap { kind in QuiltMeasurements.sizes.compactMap { size in
            let count = pieces.filter { $0.fabricID == fabric.id && $0.kind == kind && $0.size == size }.count
            return count == 0 ? nil : SummaryRow(fabric: fabric, kind: kind, size: size, count: count)
        } } }
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    public static func decoded(_ data: Data) throws -> Quilt {
        let quilt = try JSONDecoder().decode(Self.self, from: data)
        guard quilt.schemaVersion == 1 else { throw QuiltError.unsupportedVersion }
        let ids = Set(quilt.fabrics.map(\.id))
        guard quilt.units == "inches", !quilt.fabrics.isEmpty,
              ids.count == quilt.fabrics.count,
              Set(quilt.pieces.map(\.id)).count == quilt.pieces.count,
              quilt.fabrics.allSatisfy({ $0.hex.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }),
              quilt.pieces.allSatisfy({ QuiltMeasurements.sizes.contains($0.size) && (0..<6).contains($0.rotation) && ids.contains($0.fabricID) && (-1_000_000.0...1_000_000.0).contains($0.origin.q) && (-1_000_000.0...1_000_000.0).contains($0.origin.r) && ($0.origin.q * 4).rounded() == $0.origin.q * 4 && ($0.origin.r * 4).rounded() == $0.origin.r * 4 })
        else { throw QuiltError.invalidData }
        return quilt
    }
    public static func star() -> Quilt {
        var quilt = Quilt(); quilt.title = "Juniper Star"
        for rotation in 0..<6 {
            quilt.pieces.append(Piece(kind: .diamond, rotation: rotation, fabricID: quilt.fabrics[rotation % 2].id))
            let p = GridPoint(2, 2).rotated(rotation)
            quilt.pieces.append(Piece(kind: .triangle, origin: p, rotation: (rotation + 1) % 6, fabricID: quilt.fabrics[2].id))
        }
        return quilt
    }
}

public enum QuiltError: LocalizedError {
    case unsupportedVersion, invalidData
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This quilt uses a newer file format. Open it with a newer version of Poly Tool."
        case .invalidData: return "The quilt contains invalid sizes, colors, coordinates, or fabric references."
        }
    }
}

public enum QuiltMeasurements {
    public static let sizes: [Double] = (2...16).map { Double($0) / 2 }
    public static func inches(_ value: Double) -> String {
        let whole = Int(value)
        return value == Double(whole) ? "\(whole)″" : "\(whole)½″"
    }
}
