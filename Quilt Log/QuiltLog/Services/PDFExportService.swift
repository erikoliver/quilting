import AppKit
import Foundation

enum PDFExportService {
    static func export(
        preset: PDFExportPreset,
        quilts: [Quilt],
        photosByQuiltID: [Int64: [QuiltPhoto]],
        to url: URL
    ) throws {
        switch preset {
        case .completeLog:
            try exportTable(
                title: "Erik Oliver Quilt Log",
                subtitle: "Complete Log",
                quilts: quilts,
                photosByQuiltID: photosByQuiltID,
                to: url,
                includesRecipient: true
            )
        case .availableToGift:
            try exportTable(
                title: "Erik Oliver Quilt Log",
                subtitle: "Available to Gift",
                quilts: quilts.filter { isAvailable($0) },
                photosByQuiltID: photosByQuiltID,
                to: url,
                includesRecipient: false
            )
        case .visualCatalog:
            try exportVisualCatalog(
                quilts: quilts,
                photosByQuiltID: photosByQuiltID,
                to: url
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
        let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let headerFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 8.2)
        let boldFont = NSFont.systemFont(ofSize: 8.2, weight: .semibold)
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
            draw(subtitle, in: CGRect(x: 560, y: 572, width: 156, height: 14), font: NSFont.systemFont(ofSize: 10), alignment: .right)

            var x = left
            for column in columns {
                NSColor.systemGray.withAlphaComponent(0.35).setFill()
                NSRect(x: x, y: top, width: column.1, height: 20).fill()
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
                    NSColor.separatorColor.setStroke()
                    NSBezierPath(rect: NSRect(x: x, y: y, width: column.1, height: rowHeight)).stroke()
                    if columnIndex < values.count {
                        draw(values[columnIndex], in: CGRect(x: x + 3, y: y + rowHeight - 20, width: column.1 - 6, height: 14), font: columnIndex == 1 ? boldFont : bodyFont)
                    } else if let image = coverImage(for: quilt, photosByQuiltID: photosByQuiltID) {
                        drawImage(image, in: NSRect(x: x + 8, y: y + 4, width: column.1 - 16, height: rowHeight - 8))
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
        quilts: [Quilt],
        photosByQuiltID: [Int64: [QuiltPhoto]],
        to url: URL
    ) throws {
        let page = CGRect(x: 0, y: 0, width: 792, height: 612)
        let context = try makeContext(page: page)
        let titleFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let nameFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let metaFont = NSFont.systemFont(ofSize: 9)
        let left: CGFloat = 34
        let top: CGFloat = 540
        let cardWidth: CGFloat = 230
        let cardHeight: CGFloat = 152
        let hGap: CGFloat = 17
        let vGap: CGFloat = 12
        let perPage = 9

        for chunkStart in stride(from: 0, to: quilts.count, by: perPage) {
            beginPage(context, page: page)
            draw("Visual Catalog of Quilts by Erik Oliver as of \(asOfDateString())", in: CGRect(x: left, y: 570, width: 500, height: 18), font: titleFont)

            for offset in 0..<perPage {
                let index = chunkStart + offset
                guard index < quilts.count else { break }
                let quilt = quilts[index]
                let column = offset % 3
                let row = offset / 3
                let x = left + CGFloat(column) * (cardWidth + hGap)
                let y = top - CGFloat(row + 1) * cardHeight - CGFloat(row) * vGap
                let imageRect = NSRect(x: x, y: y + 36, width: cardWidth, height: cardHeight - 36)

                let cardPath = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: cardWidth, height: cardHeight), xRadius: 6, yRadius: 6)
                if isAvailable(quilt) {
                    NSColor.systemGreen.setStroke()
                    cardPath.lineWidth = 2.4
                } else {
                    NSColor.separatorColor.setStroke()
                    cardPath.lineWidth = 1
                }
                cardPath.stroke()

                if let image = coverImage(for: quilt, photosByQuiltID: photosByQuiltID) {
                    drawImage(image, in: imageRect.insetBy(dx: 8, dy: 8))
                } else {
                    NSColor.quaternaryLabelColor.setFill()
                    NSBezierPath(roundedRect: imageRect.insetBy(dx: 8, dy: 8), xRadius: 4, yRadius: 4).fill()
                    draw("No photo", in: CGRect(x: x + 76, y: y + 86, width: 90, height: 18), font: metaFont, color: .secondaryLabelColor)
                }

                draw("#\(quilt.sequenceNumber)  \(quilt.quiltName)", in: CGRect(x: x + 8, y: y + 19, width: cardWidth - 16, height: 16), font: nameFont)
                draw(visualCatalogMetaLine(for: quilt), in: CGRect(x: x + 8, y: y + 6, width: cardWidth - 16, height: 12), font: metaFont, color: isAvailable(quilt) ? .systemGreen : .secondaryLabelColor)
            }

            drawFooter(context, page: page, pageNumber: chunkStart / perPage + 1)
            endPage(context)
        }

        try finish(context, to: url)
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
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf.context, flipped: false)
    }

    private static func endPage(_ pdf: (context: CGContext, data: NSMutableData)) {
        NSGraphicsContext.restoreGraphicsState()
        pdf.context.endPDFPage()
    }

    private static func finish(_ pdf: (context: CGContext, data: NSMutableData), to url: URL) throws {
        pdf.context.closePDF()
        try pdf.data.write(to: url, options: .atomic)
    }

    private static func coverImage(for quilt: Quilt, photosByQuiltID: [Int64: [QuiltPhoto]]) -> NSImage? {
        let photos = photosByQuiltID[quilt.id] ?? []
        let photo = photos.first(where: \.isCover) ?? photos.first
        guard let data = photo?.thumbnailData else { return nil }
        return NSImage(data: data)
    }

    private static func isAvailable(_ quilt: Quilt) -> Bool {
        !quilt.giftedAlready
    }

    private static func availabilityLabel(for quilt: Quilt) -> String {
        isAvailable(quilt) ? "Available" : "Unavailable"
    }

    private static func visualCatalogMetaLine(for quilt: Quilt) -> String {
        let size = quilt.approxSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if size.isEmpty {
            return availabilityLabel(for: quilt)
        }
        return "\(size) - \(availabilityLabel(for: quilt))"
    }

    private static func asOfDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func drawFooter(_ pdf: (context: CGContext, data: NSMutableData), page: CGRect, pageNumber: Int) {
        draw(String(pageNumber), in: CGRect(x: page.midX - 15, y: 24, width: 30, height: 14), font: NSFont.systemFont(ofSize: 12), alignment: .center)
        draw(Date.now.formatted(date: .numeric, time: .omitted), in: CGRect(x: 36, y: 24, width: 120, height: 14), font: NSFont.systemFont(ofSize: 10))
    }

    private static func drawImage(_ image: NSImage, in rect: NSRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = NSRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor = .labelColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        text.draw(in: rect, withAttributes: attributes)
    }
}
