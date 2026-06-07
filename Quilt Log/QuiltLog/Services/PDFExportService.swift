// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import ImageIO
#if os(iOS)
import CoreText
#endif

enum PDFExportService {
    #if os(macOS)
    private typealias PlatformFont = NSFont
    private typealias PlatformColor = NSColor
    private typealias PlatformBezierPath = NSBezierPath
    #else
    private typealias PlatformFont = UIFont
    private typealias PlatformColor = UIColor
    private typealias PlatformBezierPath = UIBezierPath
    #endif

    private static let pdfImagePixelsPerPoint: CGFloat = 1
    private static let pdfImageJPEGCompression: CGFloat = 0.55

    static func export(
        preset: PDFExportPreset,
        ownerName: String,
        quilts: [Quilt],
        photosByQuiltID: [Int64: [QuiltPhoto]],
        to url: URL
    ) throws {
        let ownerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch preset {
        case .completeLog:
            try exportTable(
                title: logTitle(ownerName: ownerName),
                subtitle: "Complete Log",
                quilts: quilts,
                photosByQuiltID: photosByQuiltID,
                to: url,
                includesRecipient: true
            )
        case .availableToGift:
            try exportAvailableToGiftCatalog(
                title: availableToGiftTitle(ownerName: ownerName),
                quilts: quilts.filter { isAvailable($0) },
                photosByQuiltID: photosByQuiltID,
                to: url
            )
        case .visualCatalog:
            try exportVisualCatalog(
                title: visualCatalogTitle(ownerName: ownerName),
                sections: [(nil, quilts)],
                photosByQuiltID: photosByQuiltID,
                to: url,
                emphasizesAvailability: true
            )
        }
    }

    private static func exportTable(
        title: String,
        subtitle: String,
        quilts: [Quilt],
        photosByQuiltID: [Int64: [QuiltPhoto]],
        to url: URL,
        includesRecipient: Bool
    ) throws {
        let page = CGRect(x: 0, y: 0, width: 792, height: 612)
        let context = try makeContext(page: page)
        let titleFont = PlatformFont.systemFont(ofSize: 15, weight: .semibold)
        let headerFont = PlatformFont.systemFont(ofSize: 8.5, weight: .semibold)
        let bodyFont = PlatformFont.systemFont(ofSize: 8.2)
        let boldFont = PlatformFont.systemFont(ofSize: 8.2, weight: .semibold)
        let columns: [(String, CGFloat)] = includesRecipient
            ? [
                ("Seq", 30), ("Quilt Name", 112), ("Pattern", 118), ("Fabric", 106),
                ("Size", 62), ("Date", 56), ("Status", 78), ("Recipient", 86), ("Image", 70),
            ]
            : [
                ("Seq", 30), ("Quilt Name", 126), ("Pattern", 132), ("Fabric", 120),
                ("Size", 68), ("Date", 60), ("Status", 84), ("Image", 100),
            ]
        let left: CGFloat = 36
        let top: CGFloat = 536
        let rowHeight: CGFloat = 54
        let rowsPerPage = 8

        for chunkStart in stride(from: 0, to: quilts.count, by: rowsPerPage) {
            beginPage(context, page: page)
            draw("\(title) as of \(asOfDateString())", in: CGRect(x: left, y: 570, width: 340, height: 18), font: titleFont)
            draw(subtitle, in: CGRect(x: 560, y: 572, width: 156, height: 14), font: PlatformFont.systemFont(ofSize: 10), alignment: .right)

            var x = left
            for column in columns {
                PlatformColor.systemGray.withAlphaComponent(0.35).setFill()
                PlatformBezierPath(rect: CGRect(x: x, y: top, width: column.1, height: 20)).fill()
                draw(column.0, in: CGRect(x: x + 3, y: top + 5, width: column.1 - 6, height: 11), font: headerFont)
                x += column.1
            }

            for offset in 0..<rowsPerPage {
                let index = chunkStart + offset
                guard index < quilts.count else { break }
                let quilt = quilts[index]
                let y = top - CGFloat(offset + 1) * rowHeight
                x = left
                var values = [
                    String(quilt.sequenceNumber), quilt.quiltName, quilt.patternName, quilt.fabricReminder,
                    quilt.approxSize, quilt.quiltDate, quilt.status,
                ]
                if includesRecipient {
                    values.append(quilt.recipient)
                }

                for (columnIndex, column) in columns.enumerated() {
                    separatorColor.setStroke()
                    PlatformBezierPath(rect: CGRect(x: x, y: y, width: column.1, height: rowHeight)).stroke()
                    if columnIndex < values.count {
                        drawWrapped(
                            values[columnIndex],
                            in: CGRect(x: x + 3, y: y + 4, width: column.1 - 6, height: rowHeight - 8),
                            font: columnIndex == 1 ? boldFont : bodyFont
                        )
                    } else if let imageData = coverImageData(for: quilt, photosByQuiltID: photosByQuiltID) {
                        drawImage(imageData, in: CGRect(x: x + 8, y: y + 4, width: column.1 - 16, height: rowHeight - 8))
                    }
                    x += column.1
                }
            }

            drawFooter(context, page: page, pageNumber: chunkStart / rowsPerPage + 1)
            endPage(context)
        }

        try finish(context, to: url)
    }

    private static func exportVisualCatalog(
        title: String,
        sections: [(heading: String?, quilts: [Quilt])],
        photosByQuiltID: [Int64: [QuiltPhoto]],
        to url: URL,
        emphasizesAvailability: Bool
    ) throws {
        let page = CGRect(x: 0, y: 0, width: 792, height: 612)
        let context = try makeContext(page: page)
        let titleFont = PlatformFont.systemFont(ofSize: 16, weight: .semibold)
        let sectionHeadingFont = PlatformFont.systemFont(ofSize: 15, weight: .bold)
        let nameFont = PlatformFont.systemFont(ofSize: 11, weight: .semibold)
        let metaFont = PlatformFont.systemFont(ofSize: 9)
        let left: CGFloat = 34
        let top: CGFloat = 540
        let cardWidth: CGFloat = 230
        let cardHeight: CGFloat = 152
        let hGap: CGFloat = 17
        let vGap: CGFloat = 12
        let perPage = 9

        var pageNumber = 1
        for section in sections where !section.quilts.isEmpty {
            for chunkStart in stride(from: 0, to: section.quilts.count, by: perPage) {
                beginPage(context, page: page)
                draw("\(title) as of \(asOfDateString())", in: CGRect(x: left, y: 570, width: 500, height: 18), font: titleFont)
                if let heading = section.heading {
                    draw(
                        heading,
                        in: CGRect(x: page.midX - 120, y: 546, width: 240, height: 22),
                        font: sectionHeadingFont,
                        color: PlatformColor.systemIndigo,
                        alignment: .center
                    )
                }

                for offset in 0..<perPage {
                    let index = chunkStart + offset
                    guard index < section.quilts.count else { break }
                    let quilt = section.quilts[index]
                    let column = offset % 3
                    let row = offset / 3
                    let x = left + CGFloat(column) * (cardWidth + hGap)
                    let y = top - CGFloat(row + 1) * cardHeight - CGFloat(row) * vGap
                    let imageRect = CGRect(x: x, y: y + 36, width: cardWidth, height: cardHeight - 36)

                    let cardPath = roundedPath(in: CGRect(x: x, y: y, width: cardWidth, height: cardHeight), radius: 6)
                    if emphasizesAvailability, isAvailable(quilt) {
                        PlatformColor.systemGreen.setStroke()
                        cardPath.lineWidth = 2.4
                    } else {
                        separatorColor.setStroke()
                        cardPath.lineWidth = 1
                    }
                    cardPath.stroke()

                    if let imageData = coverImageData(for: quilt, photosByQuiltID: photosByQuiltID) {
                        drawImage(imageData, in: imageRect.insetBy(dx: 8, dy: 8))
                    } else {
                        quaternaryLabelColor.setFill()
                        roundedPath(in: imageRect.insetBy(dx: 8, dy: 8), radius: 4).fill()
                        draw("No photo", in: CGRect(x: x + 76, y: y + 86, width: 90, height: 18), font: metaFont, color: secondaryLabelColor)
                    }

                    draw("#\(quilt.sequenceNumber)  \(quilt.quiltName)", in: CGRect(x: x + 8, y: y + 19, width: cardWidth - 16, height: 16), font: nameFont)
                    draw(
                        visualCatalogMetaLine(for: quilt),
                        in: CGRect(x: x + 8, y: y + 6, width: cardWidth - 16, height: 12),
                        font: metaFont
                    )
                }

                drawFooter(context, page: page, pageNumber: pageNumber)
                endPage(context)
                pageNumber += 1
            }
        }

        try finish(context, to: url)
    }

    private static func exportAvailableToGiftCatalog(
        title: String,
        quilts: [Quilt],
        photosByQuiltID: [Int64: [QuiltPhoto]],
        to url: URL
    ) throws {
        let readyNow = quilts.filter { isReadyNowStatus($0.status) }
        let comingSoon = quilts.filter { !isReadyNowStatus($0.status) }
        try exportVisualCatalog(
            title: title,
            sections: [
                ("Ready Now", readyNow),
                ("Coming Soon", comingSoon),
            ],
            photosByQuiltID: photosByQuiltID,
            to: url,
            emphasizesAvailability: false
        )
    }

    private static func makeContext(page: CGRect) throws -> (context: CGContext, data: NSMutableData) {
        let data = NSMutableData()
        var mediaBox = page
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SQLiteError.stepFailed("Could not create PDF context.")
        }
        return (context, data)
    }

    private static func beginPage(_ pdf: (context: CGContext, data: NSMutableData), page: CGRect) {
        pdf.context.beginPDFPage(nil)
        pdf.context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        pdf.context.fill(page)
#if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf.context, flipped: false)
#else
        UIGraphicsPushContext(pdf.context)
#endif
    }

    private static func endPage(_ pdf: (context: CGContext, data: NSMutableData)) {
#if os(macOS)
        NSGraphicsContext.restoreGraphicsState()
#else
        UIGraphicsPopContext()
#endif
        pdf.context.endPDFPage()
    }

    private static func finish(_ pdf: (context: CGContext, data: NSMutableData), to url: URL) throws {
        pdf.context.closePDF()
        try pdf.data.write(to: url, options: .atomic)
    }

    private static func coverImageData(for quilt: Quilt, photosByQuiltID: [Int64: [QuiltPhoto]]) -> Data? {
        let photos = photosByQuiltID[quilt.id] ?? []
        let photo = photos.first(where: \.isCover) ?? photos.first
        return photo?.thumbnailData
    }

    private static func isAvailable(_ quilt: Quilt) -> Bool {
        !quilt.giftedAlready
    }

    private static func isReadyNowStatus(_ status: String) -> Bool {
        status == QuiltStatus.done.rawValue || status == QuiltStatus.backFromLongarm.rawValue
    }

    private static func logTitle(ownerName: String) -> String {
        ownerName.isEmpty ? "Quilt Log" : "\(ownerName) Quilt Log"
    }

    private static func visualCatalogTitle(ownerName: String) -> String {
        ownerName.isEmpty ? "Visual Catalog of Quilts" : "Visual Catalog of Quilts by \(ownerName)"
    }

    private static func availableToGiftTitle(ownerName: String) -> String {
        ownerName.isEmpty ? "Available to Gift Quilts" : "Available to Gift Quilts by \(ownerName)"
    }

    private static func visualCatalogMetaLine(for quilt: Quilt) -> String {
        let pattern = quilt.patternName.trimmingCharacters(in: .whitespacesAndNewlines)
        let size = quilt.approxSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pattern.isEmpty, !size.isEmpty {
            return "\(pattern) - \(size)"
        }
        if !pattern.isEmpty {
            return pattern
        }
        if !size.isEmpty {
            return size
        }
        return quilt.status
    }

    private static func asOfDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func drawFooter(_ pdf: (context: CGContext, data: NSMutableData), page: CGRect, pageNumber: Int) {
        draw(String(pageNumber), in: CGRect(x: page.midX - 15, y: 24, width: 30, height: 14), font: PlatformFont.systemFont(ofSize: 12), alignment: .center)
        draw(Date.now.formatted(date: .numeric, time: .omitted), in: CGRect(x: 36, y: 24, width: 120, height: 14), font: PlatformFont.systemFont(ofSize: 10))
    }

    private static func drawImage(_ imageData: Data, in rect: CGRect) {
        guard let image = pdfImage(from: imageData, fitting: rect) else { return }
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        currentCGContext?.draw(image, in: drawRect)
    }

    private static func pdfImage(from data: Data, fitting rect: CGRect) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let maxPixelSize = max(1, Int(ceil(max(rect.width, rect.height) * pdfImagePixelsPerPoint)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let imageForCompression = opaqueImage(from: thumbnail) ?? thumbnail
        let compressedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(compressedData, "public.jpeg" as CFString, 1, nil) else {
            return imageForCompression
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: pdfImageJPEGCompression
        ]
        CGImageDestinationAddImage(destination, imageForCompression, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let compressedSource = CGImageSourceCreateWithData(compressedData as CFData, nil),
              let compressedImage = CGImageSourceCreateImageAtIndex(compressedSource, 0, nil) else {
            return imageForCompression
        }
        return compressedImage
    }

    private static func opaqueImage(from image: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return nil
        }
        PlatformColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        font: PlatformFont,
        color: PlatformColor = labelColor,
        alignment: NSTextAlignment = .left
    ) {
#if os(iOS)
        drawCoreText(text, in: rect, font: font, color: color, alignment: alignment, wraps: false)
#else
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        text.draw(in: rect, withAttributes: attributes)
#endif
    }

    private static func drawWrapped(
        _ text: String,
        in rect: CGRect,
        font: PlatformFont,
        color: PlatformColor = labelColor
    ) {
#if os(iOS)
        drawCoreText(text, in: rect, font: font, color: color, alignment: .left, wraps: true)
#else
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        text.draw(in: rect, withAttributes: attributes)
#endif
    }

#if os(iOS)
    private static func drawCoreText(
        _ text: String,
        in rect: CGRect,
        font: PlatformFont,
        color: PlatformColor,
        alignment: NSTextAlignment,
        wraps: Bool
    ) {
        guard let context = currentCGContext else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)

        context.saveGState()
        context.textMatrix = .identity

        if wraps {
            let path = CGPath(rect: rect, transform: nil)
            let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: attributedText.length),
                path,
                nil
            )
            CTFrameDraw(frame, context)
        } else {
            let line = CTLineCreateWithAttributedString(attributedText)
            let constrainedWidth = max(1, rect.width)
            let truncatedLine = CTLineCreateTruncatedLine(
                line,
                Double(constrainedWidth),
                .end,
                nil
            ) ?? line
            let bounds = CTLineGetBoundsWithOptions(truncatedLine, [])
            let x: CGFloat
            switch alignment {
            case .center:
                x = rect.midX - bounds.width / 2
            case .right:
                x = rect.maxX - bounds.width
            default:
                x = rect.minX
            }
            let y = rect.midY - bounds.height / 2 - bounds.minY
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(truncatedLine, context)
        }

        context.restoreGState()
    }
#endif

    private static var currentCGContext: CGContext? {
#if os(macOS)
        NSGraphicsContext.current?.cgContext
#else
        UIGraphicsGetCurrentContext()
#endif
    }

    private static var labelColor: PlatformColor {
#if os(macOS)
        .black
#else
        .black
#endif
    }

    private static var secondaryLabelColor: PlatformColor {
#if os(macOS)
        .darkGray
#else
        .darkGray
#endif
    }

    private static var quaternaryLabelColor: PlatformColor {
#if os(macOS)
        .quaternaryLabelColor
#else
        .systemGray5
#endif
    }

    private static var separatorColor: PlatformColor {
#if os(macOS)
        .gray
#else
        .systemGray
#endif
    }

    private static func roundedPath(in rect: CGRect, radius: CGFloat) -> PlatformBezierPath {
#if os(macOS)
        PlatformBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
#else
        PlatformBezierPath(roundedRect: rect, cornerRadius: radius)
#endif
    }
}
