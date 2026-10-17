import XCTest
@testable import PolyCore

final class QuiltTests: XCTestCase {
    func testSixtyDegreeRotationClosesAndPreservesArea() {
        let p = GridPoint(3, -2)
        XCTAssertEqual(p.rotated(6), p)
        XCTAssertEqual(p.rotated(1), GridPoint(2, 1))
        for kind in PieceKind.allCases { for size in QuiltMeasurements.sizes { for rotation in 0..<6 {
            let piece = Piece(kind: kind, size: size, rotation: rotation, fabricID: UUID())
            let points = piece.vertices
            let area = abs(points.indices.reduce(0.0) { value, index in
                let next = points[(index + 1) % points.count]
                return value + points[index].x * next.y - next.x * points[index].y
            }) / 2
            XCTAssertEqual(area, piece.area, accuracy: 1e-8)
        } } }
    }
    func testSnapAtNegativeAndPositiveCoordinates() {
        for q in -10...10 { for r in -10...10 {
            let point = GridPoint(Double(q), Double(r)), xy = point.inches
            XCTAssertEqual(GridPoint.nearest(to: xy), point)
            XCTAssertEqual(GridPoint.nearest(to: CGPoint(x: xy.x + 0.04, y: xy.y - 0.05)), point)
        } }
    }
    func testSharedEdgesAreAllowedButInteriorOverlapIsNot() {
        let id = UUID()
        let a = Piece(kind: .triangle, size: 2, fabricID: id)
        let b = Piece(kind: .triangle, size: 2, origin: .init(2, 0), rotation: 1, fabricID: id)
        XCTAssertFalse(Geometry.overlaps(a, b))
        XCTAssertTrue(Geometry.overlaps(a, a))
        let small = Piece(kind: .triangle, size: 1, fabricID: id)
        XCTAssertTrue(Geometry.overlaps(a, small))
        let far = Piece(kind: .trapezoid, size: 2, origin: .init(-20, 10), fabricID: id)
        XCTAssertFalse(Geometry.overlaps(a, far))
    }
    func testSampleHasNoOverlaps() {
        let quilt = Quilt.star()
        XCTAssertEqual(quilt.pieces.count, 12)
        for piece in quilt.pieces { XCTAssertTrue(quilt.canPlace(piece), "Overlap in sample \(piece.kind) at rotation \(piece.rotation)") }
        XCTAssertEqual(quilt.summary.reduce(0) { $0 + $1.count }, quilt.pieces.count)
        XCTAssertEqual(quilt.triangleUnits, 72)
    }
    func testJSONRoundTrip() throws {
        let quilt = Quilt.star()
        let data = try quilt.encoded()
        XCTAssertEqual(try Quilt.decoded(data), quilt)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("schemaVersion"))
        XCTAssertEqual(try Quilt.decoded(Quilt().encoded()), Quilt())
    }
    func testInvalidDataIsRejected() throws {
        var quilt = Quilt.star()
        quilt.schemaVersion = 99
        XCTAssertThrowsError(try Quilt.decoded(quilt.encoded()))
        quilt.schemaVersion = 1; quilt.pieces[0].size = 0
        XCTAssertThrowsError(try Quilt.decoded(quilt.encoded()))
        quilt.pieces[0].size = 2; quilt.pieces[0].fabricID = UUID()
        XCTAssertThrowsError(try Quilt.decoded(quilt.encoded()))
        quilt = Quilt.star(); quilt.fabrics[0].hex = "not-a-color"
        XCTAssertThrowsError(try Quilt.decoded(quilt.encoded()))
        quilt = Quilt.star(); quilt.pieces[0].origin = .init(Double(Int.max), 0)
        XCTAssertThrowsError(try Quilt.decoded(quilt.encoded()))
        quilt = Quilt.star(); quilt.fabrics = []
        XCTAssertThrowsError(try Quilt.decoded(quilt.encoded()))
    }
    func testTwoSmallRowsMatchOneDefaultRow() {
        XCTAssertEqual(GridPoint(0, 2).inches.y, 2)
        let large = Piece(kind: .triangle, size: 2, fabricID: UUID())
        let small = Piece(kind: .triangle, size: 1, fabricID: UUID())
        XCTAssertEqual(large.area, small.area * 4, accuracy: 1e-8)
        XCTAssertEqual(large.bounds.height, 2)
        XCTAssertEqual(large.nominalStrip, 2.5)
    }
    func testFullRulerRangeAndHalfInchSnapping() throws {
        XCTAssertEqual(QuiltMeasurements.sizes.count, 15)
        XCTAssertEqual(QuiltMeasurements.sizes.first, 1)
        XCTAssertEqual(QuiltMeasurements.sizes.last, 8)
        var quilt = Quilt()
        for (index, size) in QuiltMeasurements.sizes.enumerated() {
            quilt.pieces.append(Piece(kind: .triangle, size: size, origin: .init(Double(index) * 20 + 0.5, -0.5), fabricID: quilt.fabrics[0].id))
        }
        XCTAssertEqual(try Quilt.decoded(quilt.encoded()), quilt)
        XCTAssertEqual(quilt.summary.count, 15)
        XCTAssertEqual(GridPoint.nearest(to: GridPoint(1.5, -2.5).inches), GridPoint(1.5, -2.5))
        quilt.pieces[0].size = 2.25
        XCTAssertThrowsError(try Quilt.decoded(quilt.encoded()))
        XCTAssertEqual(QuiltMeasurements.inches(8.5), "8½″")
    }
    func testAllShapesPersistAndSummarize() throws {
        var quilt = Quilt()
        for (index, kind) in PieceKind.allCases.enumerated() {
            for size in QuiltMeasurements.sizes {
                quilt.pieces.append(Piece(kind: kind, size: size, origin: .init(Double(index) * 100, size * 30), fabricID: quilt.fabrics[0].id))
            }
        }
        XCTAssertEqual(PieceKind.allCases.count, 8)
        XCTAssertEqual(try Quilt.decoded(quilt.encoded()), quilt)
        XCTAssertEqual(quilt.summary.count, 120)
        XCTAssertEqual(quilt.summary.reduce(0) { $0 + $1.count }, 120)
    }
    func testHexagonHasSixEqualSidesAndSpecifiedHeight() {
        let hexagon = Piece(kind: .hexagon, size: 3.5, fabricID: UUID())
        let points = hexagon.vertices
        XCTAssertEqual(hexagon.bounds.height, 3.5, accuracy: 1e-8)
        for i in points.indices {
            let next = points[(i + 1) % points.count]
            XCTAssertEqual(hypot(next.x - points[i].x, next.y - points[i].y), 3.5 / sqrt(3), accuracy: 1e-8)
        }
        XCTAssertEqual(GridPoint.nearest(to: GridPoint(1.75, -0.25).inches), GridPoint(1.75, -0.25))
    }
    func testSideSettingTriangleHas120DegreeApex() {
        let piece = Piece(kind: .sideSettingTriangle, size: 2, fabricID: UUID())
        let p = piece.vertices
        let u = CGPoint(x: p[1].x - p[0].x, y: p[1].y - p[0].y)
        let v = CGPoint(x: p[2].x - p[0].x, y: p[2].y - p[0].y)
        let angle = acos((u.x * v.x + u.y * v.y) / (hypot(u.x, u.y) * hypot(v.x, v.y)))
        XCTAssertEqual(angle * 180 / .pi, 120, accuracy: 1e-8)
        XCTAssertEqual(hypot(u.x, u.y), hypot(v.x, v.y), accuracy: 1e-8)
        XCTAssertEqual(piece.bounds.height, 2)
    }
    func testDahliaJewelAndTipReconstructDiamond() {
        let id = UUID()
        for rotation in 0..<6 {
            let jewel = Piece(kind: .jewel, size: 2, rotation: rotation, fabricID: id)
            let tip = Piece(kind: .triangle, size: 1, origin: GridPoint(2, 2).rotated(rotation), rotation: (rotation + 3) % 6, fabricID: id)
            let diamond = Piece(kind: .diamond, size: 2, rotation: rotation, fabricID: id)
            XCTAssertEqual(jewel.vertices.count, 5)
            XCTAssertFalse(Geometry.overlaps(jewel, tip))
            XCTAssertTrue(Geometry.overlaps(jewel, diamond))
            XCTAssertEqual(jewel.area + tip.area, diamond.area, accuracy: 1e-8)
        }
    }
    func testRegularSideTrianglesAreMirrorsAndFillOneTriangle() {
        let id = UUID()
        for size in QuiltMeasurements.sizes { for rotation in 0..<6 {
            let left = Piece(kind: .sideTriangle, size: size, rotation: rotation, fabricID: id)
            let right = Piece(kind: .sideTriangle, size: size, origin: GridPoint(size, 0).rotated(rotation), rotation: rotation, fabricID: id, flipped: true)
            let full = Piece(kind: .triangle, size: size, rotation: rotation, fabricID: id)
            XCTAssertFalse(Geometry.overlaps(left, right))
            XCTAssertEqual(left.area + right.area, full.area, accuracy: 1e-8)
            let points = left.vertices
            let a = CGPoint(x: points[0].x - points[1].x, y: points[0].y - points[1].y)
            let b = CGPoint(x: points[2].x - points[1].x, y: points[2].y - points[1].y)
            XCTAssertEqual(a.x * b.x + a.y * b.y, 0, accuracy: 1e-8)
            XCTAssertEqual(left.area, right.area, accuracy: 1e-8)
        } }
    }
    func testFlipTwiceRestoresEveryShapeAndPreservesArea() throws {
        var quilt = Quilt()
        for kind in PieceKind.allCases { for rotation in 0..<6 {
            var piece = Piece(kind: kind, size: 2.5, origin: .init(4, -2), rotation: rotation, fabricID: quilt.fabrics[0].id)
            let original = piece.vertices
            piece.flipped = true
            let points = piece.vertices
            let area = abs(points.indices.reduce(0.0) { sum, i in
                let next = points[(i + 1) % points.count]
                return sum + points[i].x * next.y - next.x * points[i].y
            }) / 2
            XCTAssertEqual(area, piece.area, accuracy: 1e-8)
            XCTAssertTrue(Geometry.overlaps(piece, piece))
            quilt.pieces.append(piece)
            piece.flipped.toggle()
            XCTAssertEqual(piece.vertices, original)
        } }
        XCTAssertEqual(try Quilt.decoded(quilt.encoded()), quilt)
    }
}
