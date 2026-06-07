// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum TemplateShape: String, CaseIterable, Identifiable {
    case square
    case vblock
    case cornerbeam
    case squareinsquare
    case economy
    case vintagekite
    case turkeygiblets

    static var selectableCases: [TemplateShape] {
        [.vblock, .cornerbeam, .squareinsquare, .economy, .vintagekite, .turkeygiblets]
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .square: return "Square"
        case .vblock: return "V-block / Triangle-in-square"
        case .cornerbeam: return "Corner beam / Kite"
        case .squareinsquare: return "Square-in-square"
        case .economy: return "Economy block"
        case .vintagekite: return "Vintage kite"
        case .turkeygiblets: return "Turkey Giblets"
        }
    }
}

struct TemplateSpec {
    let shape: TemplateShape
    let finishedSizeInches: Double
    let debug: Bool

    var outerSizeInches: Double {
        finishedSizeInches + TemplateRenderer.seamAllowanceInches * 2
    }
}

struct TemplateRenderer {
    static let pointsPerInch = 72.0
    static let letterWidthInches = 8.5
    static let letterHeightInches = 11.0
    static let seamAllowanceInches = 0.25

    let spec: TemplateSpec

    func writePDF(to url: URL) throws {
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: Self.letterWidthInches * Self.pointsPerInch,
            height: Self.letterHeightInches * Self.pointsPerInch
        )

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        drawPDF(in: context)
        context.endPDFPage()
        context.closePDF()
    }

    func drawPreview(in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width / Self.letterWidthInches, size.height / Self.letterHeightInches)
        let xOffset = (size.width - Self.letterWidthInches * scale) / 2
        let yOffset = (size.height - Self.letterHeightInches * scale) / 2

        let commands = drawingCommands()
        for command in commands {
            switch command {
            case .line(let start, let end, let style):
                var path = Path()
                path.move(to: previewPoint(start, scale: scale, xOffset: xOffset, yOffset: yOffset))
                path.addLine(to: previewPoint(end, scale: scale, xOffset: xOffset, yOffset: yOffset))
                context.stroke(path, with: .color(style.color), style: style.strokeStyle(scale: scale))
            case .rect(let rect, let style):
                let previewRect = CGRect(
                    x: xOffset + rect.minX * scale,
                    y: yOffset + (Self.letterHeightInches - rect.maxY) * scale,
                    width: rect.width * scale,
                    height: rect.height * scale
                )
                context.stroke(Path(previewRect), with: .color(style.color), style: style.strokeStyle(scale: scale))
            case .polygon(let points, let style):
                guard let first = points.first else { continue }
                var path = Path()
                path.move(to: previewPoint(first, scale: scale, xOffset: xOffset, yOffset: yOffset))
                for point in points.dropFirst() {
                    path.addLine(to: previewPoint(point, scale: scale, xOffset: xOffset, yOffset: yOffset))
                }
                path.closeSubpath()
                context.stroke(path, with: .color(style.color), style: style.strokeStyle(scale: scale))
            case .text(let point, let value, let fontSize, let centered):
                let resolved = context.resolve(Text(value).font(.system(size: fontSize * scale / Self.pointsPerInch)))
                let target = previewPoint(point, scale: scale, xOffset: xOffset, yOffset: yOffset)
                context.draw(resolved, at: target, anchor: centered ? .center : .bottomLeading)
            }
        }
    }

    private func drawPDF(in context: CGContext) {
        for command in drawingCommands() {
            switch command {
            case .line(let start, let end, let style):
                apply(style, to: context)
                context.move(to: pdfPoint(start))
                context.addLine(to: pdfPoint(end))
                context.strokePath()
            case .rect(let rect, let style):
                apply(style, to: context)
                context.stroke(CGRect(
                    x: rect.minX * Self.pointsPerInch,
                    y: rect.minY * Self.pointsPerInch,
                    width: rect.width * Self.pointsPerInch,
                    height: rect.height * Self.pointsPerInch
                ))
            case .polygon(let points, let style):
                guard let first = points.first else { continue }
                apply(style, to: context)
                context.move(to: pdfPoint(first))
                for point in points.dropFirst() {
                    context.addLine(to: pdfPoint(point))
                }
                context.closePath()
                context.strokePath()
            case .text(let point, let value, let fontSize, let centered):
                drawPDFText(value, at: point, fontSize: fontSize, centered: centered, in: context)
            }
        }
    }

    private func drawingCommands() -> [DrawCommand] {
        var drawing = TemplateDrawing()
        switch spec.shape {
        case .square:
            drawSquare(into: &drawing)
        case .vblock:
            drawVBlock(into: &drawing)
        case .cornerbeam:
            drawCornerBeam(into: &drawing)
        case .squareinsquare:
            drawSquareInSquare(into: &drawing)
        case .economy:
            drawEconomy(into: &drawing)
        case .vintagekite:
            drawVintageKite(into: &drawing)
        case .turkeygiblets:
            drawTurkeyGiblets(into: &drawing)
        }
        return drawing.commands
    }

    private func bounds() -> TemplateBounds {
        let outer = spec.outerSizeInches
        let left = (Self.letterWidthInches - outer) / 2
        let bottom = Self.letterHeightInches - 1.0 - outer
        return TemplateBounds(left: left, bottom: bottom, outer: outer, finished: spec.finishedSizeInches)
    }

    private func drawFrame(into drawing: inout TemplateDrawing, bounds: TemplateBounds) {
        drawing.rect(bounds.outerRect, style: .cut)
        drawing.rect(bounds.innerRect, style: .seam)

        if spec.debug {
            let centerX = bounds.left + bounds.outer / 2
            let centerY = bounds.bottom + bounds.outer / 2
            drawing.line(Point(centerX, bounds.bottom), Point(centerX, bounds.top), style: .debug)
            drawing.line(Point(bounds.left, centerY), Point(bounds.right, centerY), style: .debug)
        }
    }

    private func drawLabels(into drawing: inout TemplateDrawing, bounds: TemplateBounds) {
        drawing.text(Point(bounds.left, bounds.bottom - 0.28), "\(spec.shape.displayName) foundation template", size: 10)
        drawing.text(Point(bounds.left, bounds.bottom - 0.46), "Finished size: \(inchLabel(spec.finishedSizeInches))\" x \(inchLabel(spec.finishedSizeInches))\"", size: 9)
        drawing.text(Point(bounds.left, bounds.bottom - 0.64), "Cut size with fixed 1/4\" seam allowance: \(inchLabel(spec.outerSizeInches))\" x \(inchLabel(spec.outerSizeInches))\"", size: 9)

        let referenceLeft = bounds.right - 1.0
        let referenceBottom = bounds.bottom - 1.75
        drawing.rect(CGRect(x: referenceLeft, y: referenceBottom, width: 1.0, height: 1.0), style: .cut)
        drawing.centeredText(Point(referenceLeft + 0.5, referenceBottom + 0.5), "1\"", size: 12)
        drawing.centeredText(Point(referenceLeft + 0.5, referenceBottom - 0.18), "Print check", size: 8)
    }

    private func drawSquare(into drawing: inout TemplateDrawing) {
        let b = bounds()
        drawFrame(into: &drawing, bounds: b)
        drawing.centeredText(Point(Self.letterWidthInches / 2, b.bottom + b.outer / 2), "1", size: 20)
        drawLabels(into: &drawing, bounds: b)
    }

    private func drawVBlock(into drawing: inout TemplateDrawing) {
        let b = bounds()
        drawFrame(into: &drawing, bounds: b)
        let apex = Point(b.innerLeft + b.finished / 2, b.innerTop)
        drawing.line(apex, Point(b.innerLeft, b.innerBottom), style: .seam)
        drawing.line(apex, Point(b.innerRight, b.innerBottom), style: .seam)
        drawing.centeredText(Point(apex.x, b.innerBottom + b.finished * 0.38), "1", size: 18)
        drawing.centeredText(Point(b.innerLeft + b.finished * 0.22, b.innerBottom + b.finished * 0.64), "2", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished * 0.78, b.innerBottom + b.finished * 0.64), "3", size: 16)
        drawCross(at: apex, into: &drawing)
        drawLabels(into: &drawing, bounds: b)
    }

    private func drawCornerBeam(into drawing: inout TemplateDrawing) {
        let b = bounds()
        drawFrame(into: &drawing, bounds: b)
        let half = b.finished / 2
        let thin = Point(b.innerRight, b.innerTop)
        drawing.line(thin, Point(b.innerLeft, b.innerTop - half), style: .seam)
        drawing.line(thin, Point(b.innerRight - half, b.innerBottom), style: .seam)
        drawing.centeredText(Point(b.innerLeft + b.finished * 0.43, b.innerBottom + b.finished * 0.43), "1", size: 18)
        drawing.centeredText(Point(b.innerLeft + b.finished * 0.36, b.innerBottom + b.finished * 0.79), "2", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished * 0.79, b.innerBottom + b.finished * 0.36), "3", size: 16)
        drawCross(at: thin, into: &drawing)
        drawLabels(into: &drawing, bounds: b)
    }

    private func drawSquareInSquare(into drawing: inout TemplateDrawing) {
        let b = bounds()
        drawFrame(into: &drawing, bounds: b)
        let center = Point(b.innerLeft + b.finished / 2, b.innerBottom + b.finished / 2)
        drawing.polygon([
            Point(center.x, b.innerTop),
            Point(b.innerRight, center.y),
            Point(center.x, b.innerBottom),
            Point(b.innerLeft, center.y)
        ], style: .seam)
        drawing.centeredText(Point(center.x, center.y - 0.05), "1", size: 18)
        drawing.centeredText(Point(b.innerLeft + b.finished / 6, b.innerBottom + b.finished * 5 / 6), "2", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished * 5 / 6, b.innerBottom + b.finished * 5 / 6), "3", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished * 5 / 6, b.innerBottom + b.finished / 6), "4", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished / 6, b.innerBottom + b.finished / 6), "5", size: 16)
        drawLabels(into: &drawing, bounds: b)
    }

    private func drawEconomy(into drawing: inout TemplateDrawing) {
        let b = bounds()
        drawFrame(into: &drawing, bounds: b)
        let center = Point(b.innerLeft + b.finished / 2, b.innerBottom + b.finished / 2)
        drawing.polygon([
            Point(center.x, b.innerTop),
            Point(b.innerRight, center.y),
            Point(center.x, b.innerBottom),
            Point(b.innerLeft, center.y)
        ], style: .seam)

        let quarter = b.finished / 4
        drawing.polygon([
            Point(center.x - quarter, center.y + quarter),
            Point(center.x + quarter, center.y + quarter),
            Point(center.x + quarter, center.y - quarter),
            Point(center.x - quarter, center.y - quarter)
        ], style: .seam)

        drawing.centeredText(Point(center.x, center.y - 0.05), "1", size: 18)
        drawing.centeredText(Point(center.x, center.y + b.finished / 3), "2", size: 16)
        drawing.centeredText(Point(center.x + b.finished / 3, center.y - 0.05), "3", size: 16)
        drawing.centeredText(Point(center.x, center.y - b.finished / 3), "4", size: 16)
        drawing.centeredText(Point(center.x - b.finished / 3, center.y - 0.05), "5", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished / 6, b.innerBottom + b.finished * 5 / 6), "6", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished * 5 / 6, b.innerBottom + b.finished * 5 / 6), "7", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished * 5 / 6, b.innerBottom + b.finished / 6), "8", size: 16)
        drawing.centeredText(Point(b.innerLeft + b.finished / 6, b.innerBottom + b.finished / 6), "9", size: 16)
        drawLabels(into: &drawing, bounds: b)
    }

    private func drawVintageKite(into drawing: inout TemplateDrawing) {
        let center = Point(Self.letterWidthInches / 2, 6.0)
        let halfGap = 1.25 / 2
        let units = [
            (Point(center.x, center.y - halfGap), 0.0),
            (Point(center.x + halfGap, center.y), Double.pi / 2),
            (Point(center.x, center.y + halfGap), Double.pi),
            (Point(center.x - halfGap, center.y), -Double.pi / 2)
        ]

        for unit in units {
            drawVintageKiteUnit(apex: unit.0, radians: unit.1, into: &drawing)
        }

        drawing.text(Point(1.0, 1.3), "Vintage kite foundation template", size: 10)
        drawing.text(Point(1.0, 1.12), "Finished block size: \(inchLabel(spec.finishedSizeInches))\" x \(inchLabel(spec.finishedSizeInches))\"", size: 9)
        drawing.text(Point(1.0, 0.94), "Four foundation units make one block", size: 9)
        drawing.text(Point(1.0, 0.76), "Each unit uses a finished triangle with \(inchLabel(spec.finishedSizeInches))\" base and \(inchLabel(spec.finishedSizeInches / 2))\" height", size: 9)

        let referenceLeft = 6.25
        let referenceBottom = 0.65
        drawing.rect(CGRect(x: referenceLeft, y: referenceBottom, width: 1.0, height: 1.0), style: .cut)
        drawing.centeredText(Point(referenceLeft + 0.5, referenceBottom + 0.5), "1\"", size: 12)
        drawing.centeredText(Point(referenceLeft + 0.5, referenceBottom - 0.18), "Print check", size: 8)
    }

    private func drawVintageKiteUnit(apex: Point, radians: Double, into drawing: inout TemplateDrawing) {
        let finished = spec.finishedSizeInches
        let half = finished / 2
        let finishedTriangle = [
            transform(Point(-half, -half), radians: radians, offset: apex),
            transform(Point(half, -half), radians: radians, offset: apex),
            transform(Point(0, 0), radians: radians, offset: apex)
        ]
        let outerTriangle = offsetConvexPolygon(finishedTriangle, by: Self.seamAllowanceInches)
        let kite = [
            transform(Point(0, 0), radians: radians, offset: apex),
            transform(Point(finished / 6, -finished / 6), radians: radians, offset: apex),
            transform(Point(0, -half), radians: radians, offset: apex),
            transform(Point(-finished / 6, -finished / 6), radians: radians, offset: apex)
        ]

        drawing.polygon(outerTriangle, style: .cut)
        drawing.polygon(finishedTriangle, style: .seam)
        drawing.polygon(kite, style: .seam)
        drawing.centeredText(transform(Point(-finished / 3, -finished * 5 / 12), radians: radians, offset: apex), "1", size: 14)
        drawing.centeredText(transform(Point(0, -finished / 4), radians: radians, offset: apex), "2", size: 14)
        drawing.centeredText(transform(Point(finished / 3, -finished * 5 / 12), radians: radians, offset: apex), "3", size: 14)
    }

    private func drawTurkeyGiblets(into drawing: inout TemplateDrawing) {
        let b = bounds()
        let f = b.finished
        let unitGap = 0.82
        let shift = unitGap / sqrt(2) / 2
        let lowerShift = Point(-shift, -shift)
        let lower = { point in translate(point, offset: lowerShift) }
        let upper = { point in mirrorAcrossInnerCenter(lower(point), bounds: b) }

        let triangle = [
            Point(b.innerLeft, b.innerTop),
            Point(b.innerLeft, b.innerBottom),
            Point(b.innerRight, b.innerBottom)
        ]
        let upperSideStart = Point(b.innerLeft, b.innerBottom + f * 0.52)
        let upperSideEnd = Point(b.innerLeft + f * 0.38, b.innerTop - f * 0.38)
        let lowerSideStart = Point(b.innerLeft + f * 0.52, b.innerBottom)
        let lowerSideEnd = Point(b.innerLeft + f * 0.62, b.innerTop - f * 0.62)

        if spec.debug {
            drawDiagonalGuides(into: &drawing, bounds: b)
        }

        drawTurkeyGibletsUnit(
            triangle: triangle,
            transform: lower,
            upperSideStart: upperSideStart,
            upperSideEnd: upperSideEnd,
            lowerSideStart: lowerSideStart,
            lowerSideEnd: lowerSideEnd,
            centerColor: "Color A",
            sideColor: "BG",
            into: &drawing
        )
        drawTurkeyGibletsUnit(
            triangle: triangle,
            transform: upper,
            upperSideStart: upperSideStart,
            upperSideEnd: upperSideEnd,
            lowerSideStart: lowerSideStart,
            lowerSideEnd: lowerSideEnd,
            centerColor: "BG",
            sideColor: "Color A",
            into: &drawing
        )

        let footerTop = max(1.55, b.bottom - 0.95)
        drawing.text(Point(b.left, footerTop), "Turkey Giblets foundation template", size: 10)
        drawing.text(Point(b.left, footerTop - 0.18), "Finished quadrant size: \(inchLabel(spec.finishedSizeInches))\" x \(inchLabel(spec.finishedSizeInches))\"", size: 9)
        drawing.text(Point(b.left, footerTop - 0.36), "Two triangular units make one quadrant; print 4 pages for one block.", size: 9)
        drawing.text(Point(b.left, footerTop - 0.54), "Lower unit: 1 Color A, 2/3 BG. Upper unit: 1 BG, 2/3 Color A.", size: 8)

        let referenceLeft = b.left
        let referenceBottom = max(0.25, footerTop - 1.55)
        drawing.rect(CGRect(x: referenceLeft, y: referenceBottom, width: 1.0, height: 1.0), style: .cut)
        drawing.centeredText(Point(referenceLeft + 0.5, referenceBottom + 0.5), "1\"", size: 12)
        drawing.centeredText(Point(referenceLeft + 0.5, referenceBottom - 0.18), "Print check", size: 8)
    }

    private func drawTurkeyGibletsUnit(
        triangle: [Point],
        transform: (Point) -> Point,
        upperSideStart: Point,
        upperSideEnd: Point,
        lowerSideStart: Point,
        lowerSideEnd: Point,
        centerColor: String,
        sideColor: String,
        into drawing: inout TemplateDrawing
    ) {
        guard triangle.count == 3 else { return }

        let f = spec.finishedSizeInches
        let origin = triangle[1]
        let transformedTriangle = triangle.map(transform)

        drawing.polygon(offsetConvexPolygon(transformedTriangle, by: Self.seamAllowanceInches), style: .cut)
        drawing.polygon(transformedTriangle, style: .seam)
        drawing.line(transform(upperSideStart), transform(upperSideEnd), style: .seam)
        drawing.line(transform(lowerSideStart), transform(lowerSideEnd), style: .seam)

        drawing.centeredText(transform(Point(origin.x + f * 0.30, origin.y + f * 0.30)), "1", size: 14)
        drawing.centeredText(transform(Point(origin.x + f * 0.30, origin.y + f * 0.23)), centerColor, size: 8)
        drawing.centeredText(transform(Point(origin.x + f * 0.14, origin.y + f * 0.74)), "2", size: 12)
        drawing.centeredText(transform(Point(origin.x + f * 0.14, origin.y + f * 0.68)), sideColor, size: 8)
        drawing.centeredText(transform(Point(origin.x + f * 0.74, origin.y + f * 0.14)), "3", size: 12)
        drawing.centeredText(transform(Point(origin.x + f * 0.74, origin.y + f * 0.08)), sideColor, size: 8)
    }

    private func drawDiagonalGuides(into drawing: inout TemplateDrawing, bounds: TemplateBounds) {
        drawing.line(Point(bounds.innerLeft, bounds.innerTop), Point(bounds.innerRight, bounds.innerBottom), style: .debug)
    }

    private func drawCross(at point: Point, into drawing: inout TemplateDrawing) {
        drawing.line(Point(point.x - 0.07, point.y), Point(point.x + 0.07, point.y), style: .thin)
        drawing.line(Point(point.x, point.y - 0.07), Point(point.x, point.y + 0.07), style: .thin)
    }

    private func apply(_ style: LineStyle, to context: CGContext) {
        context.setStrokeColor(NSColor(style.color).cgColor)
        context.setLineWidth(style.widthPoints)
        if let dash = style.dashPoints {
            context.setLineDash(phase: 0, lengths: dash.map { CGFloat($0) })
        } else {
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    private func drawPDFText(_ value: String, at point: Point, fontSize: Double, centered: Bool, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]
        let string = NSAttributedString(string: value, attributes: attributes)
        let size = string.size()
        let origin = CGPoint(
            x: point.x * Self.pointsPerInch - (centered ? size.width / 2 : 0),
            y: point.y * Self.pointsPerInch - (centered ? size.height / 2 : 0)
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func previewPoint(_ point: Point, scale: Double, xOffset: Double, yOffset: Double) -> CGPoint {
        CGPoint(
            x: xOffset + point.x * scale,
            y: yOffset + (Self.letterHeightInches - point.y) * scale
        )
    }

    private func pdfPoint(_ point: Point) -> CGPoint {
        CGPoint(x: point.x * Self.pointsPerInch, y: point.y * Self.pointsPerInch)
    }

    private func inchLabel(_ value: Double) -> String {
        let rounded = (value * 4).rounded() / 4
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }
}

private struct TemplateBounds {
    let left: Double
    let bottom: Double
    let outer: Double
    let finished: Double

    var right: Double { left + outer }
    var top: Double { bottom + outer }
    var innerLeft: Double { left + TemplateRenderer.seamAllowanceInches }
    var innerBottom: Double { bottom + TemplateRenderer.seamAllowanceInches }
    var innerRight: Double { innerLeft + finished }
    var innerTop: Double { innerBottom + finished }
    var outerRect: CGRect { CGRect(x: left, y: bottom, width: outer, height: outer) }
    var innerRect: CGRect { CGRect(x: innerLeft, y: innerBottom, width: finished, height: finished) }
}

private struct Point: Equatable {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

private enum DrawCommand {
    case line(Point, Point, LineStyle)
    case rect(CGRect, LineStyle)
    case polygon([Point], LineStyle)
    case text(Point, String, Double, Bool)
}

private struct TemplateDrawing {
    var commands: [DrawCommand] = []

    mutating func line(_ start: Point, _ end: Point, style: LineStyle) {
        commands.append(.line(start, end, style))
    }

    mutating func rect(_ rect: CGRect, style: LineStyle) {
        commands.append(.rect(rect, style))
    }

    mutating func polygon(_ points: [Point], style: LineStyle) {
        commands.append(.polygon(points, style))
    }

    mutating func text(_ point: Point, _ value: String, size: Double) {
        commands.append(.text(point, value, size, false))
    }

    mutating func centeredText(_ point: Point, _ value: String, size: Double) {
        commands.append(.text(point, value, size, true))
    }
}

private struct LineStyle {
    let widthPoints: Double
    let dashPoints: [Double]?
    let color: Color

    static let cut = LineStyle(widthPoints: 0.75, dashPoints: nil, color: .black)
    static let seam = LineStyle(widthPoints: 0.5, dashPoints: [2, 2], color: .black)
    static let thin = LineStyle(widthPoints: 0.4, dashPoints: nil, color: .black)
    static let debug = LineStyle(widthPoints: 0.2, dashPoints: nil, color: .red)

    func strokeStyle(scale: Double) -> StrokeStyle {
        StrokeStyle(
            lineWidth: max(widthPoints / TemplateRenderer.pointsPerInch * scale, 0.5),
            dash: (dashPoints ?? []).map { $0 / TemplateRenderer.pointsPerInch * scale }
        )
    }
}

private func transform(_ point: Point, radians: Double, offset: Point) -> Point {
    let cosAngle = cos(radians)
    let sinAngle = sin(radians)
    return Point(
        point.x * cosAngle - point.y * sinAngle + offset.x,
        point.x * sinAngle + point.y * cosAngle + offset.y
    )
}

private func translate(_ point: Point, offset: Point) -> Point {
    Point(point.x + offset.x, point.y + offset.y)
}

private func mirrorAcrossInnerCenter(_ point: Point, bounds: TemplateBounds) -> Point {
    Point(bounds.innerLeft + bounds.innerRight - point.x, bounds.innerBottom + bounds.innerTop - point.y)
}

private func polygonArea(_ points: [Point]) -> Double {
    guard points.count > 2 else { return 0 }
    return points.enumerated().reduce(0) { result, item in
        let next = points[(item.offset + 1) % points.count]
        return result + item.element.x * next.y - next.x * item.element.y
    } / 2
}

private func lineIntersection(pointA: Point, directionA: Point, pointB: Point, directionB: Point) -> Point {
    let cross = directionA.x * directionB.y - directionA.y * directionB.x
    guard abs(cross) >= 1e-9 else { return pointA }

    let delta = Point(pointB.x - pointA.x, pointB.y - pointA.y)
    let scale = (delta.x * directionB.y - delta.y * directionB.x) / cross
    return Point(pointA.x + directionA.x * scale, pointA.y + directionA.y * scale)
}

private func offsetConvexPolygon(_ input: [Point], by distance: Double) -> [Point] {
    var points = input
    if polygonArea(points) < 0 {
        points.reverse()
    }

    let offsetLines = points.enumerated().map { item -> (Point, Point) in
        let point = item.element
        let next = points[(item.offset + 1) % points.count]
        let direction = Point(next.x - point.x, next.y - point.y)
        let length = hypot(direction.x, direction.y)
        let normal = Point(direction.y / length, -direction.x / length)
        return (Point(point.x + normal.x * distance, point.y + normal.y * distance), direction)
    }

    return offsetLines.enumerated().map { item in
        let previous = offsetLines[(item.offset + offsetLines.count - 1) % offsetLines.count]
        return lineIntersection(
            pointA: previous.0,
            directionA: previous.1,
            pointB: item.element.0,
            directionB: item.element.1
        )
    }
}
