import SwiftUI
import AppKit

struct PieceDrag: Codable {
    var kind: PieceKind
    var size: Double
    var rotation: Int
    var fabricID: UUID
    var flipped: Bool
    var text: String { "polytool:" + String(data: try! JSONEncoder().encode(self), encoding: .utf8)! }
    static func parse(_ text: String?) -> Self? {
        guard let text, text.hasPrefix("polytool:"), let data = String(text.dropFirst(9)).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Self.self, from: data), QuiltMeasurements.sizes.contains(payload.size), (0..<6).contains(payload.rotation)
        else { return nil }
        return payload
    }
}

struct QuiltCanvas: NSViewRepresentable {
    @ObservedObject var document: QuiltDocument
    @ObservedObject var session: EditorSession
    var commit: (Quilt, String) -> Void
    var rotate: () -> Void
    var flip: () -> Void
    var delete: () -> Void
    var duplicate: () -> Void
    func makeNSView(context: Context) -> QuiltCanvasView {
        let view = QuiltCanvasView(); view.registerForDraggedTypes([.string]); return view
    }
    func updateNSView(_ view: QuiltCanvasView, context: Context) {
        view.quilt = document.quilt; view.session = session
        view.commit = commit; view.rotateAction = rotate; view.flipAction = flip; view.deleteAction = delete; view.duplicateAction = duplicate
        if view.lastFit != session.fitRequest {
            view.lastFit = session.fitRequest
            // Publish the viewport on the next run-loop turn, outside SwiftUI's update pass.
            DispatchQueue.main.async { [weak view] in view?.fit() }
        }
        view.needsDisplay = true
    }
}

final class QuiltCanvasView: NSView {
    var quilt = Quilt()
    var session: EditorSession!
    var commit: ((Quilt, String) -> Void)?
    var rotateAction: (() -> Void)?
    var flipAction: (() -> Void)?
    var deleteAction: (() -> Void)?
    var duplicateAction: (() -> Void)?
    var lastFit = 0
    var start = CGPoint.zero
    var startCenter = CGPoint.zero
    var moving: Piece?
    var preview: Piece?
    var didDrag = false
    var spaceDown = false
    var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(tracking!)
    }
    override func cursorUpdate(with event: NSEvent) { (session.panMode || spaceDown ? NSCursor.openHand : NSCursor.arrow).set() }
    func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - session.center.x) * session.zoom + bounds.midX, y: (p.y - session.center.y) * session.zoom + bounds.midY) }
    func world(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - bounds.midX) / session.zoom + session.center.x, y: (p.y - bounds.midY) / session.zoom + session.center.y) }
    func path(_ piece: Piece) -> NSBezierPath {
        let p = NSBezierPath(), points = piece.vertices.map(screen)
        p.move(to: points[0]); for point in points.dropFirst() { p.line(to: point) }; p.close(); return p
    }
    override func draw(_ dirtyRect: NSRect) {
        guard session != nil else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        NSColor(hex: "F8F6F0").setFill(); bounds.fill()
        if session.showGrid { drawGrid() }
        for piece in quilt.pieces where piece.id != moving?.id {
            drawPiece(piece, selected: piece.id == session.selection)
        }
        if let preview {
            let valid = quilt.canPlace(preview)
            drawPiece(preview, selected: true, opacity: 0.7)
            if !valid { NSColor.systemRed.setStroke(); let p = path(preview); p.lineWidth = 3; p.stroke() }
        }
        if quilt.pieces.isEmpty && preview == nil {
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor(hex: "7D8880"), .paragraphStyle: style]
            "A little geometry. Endless possibilities.".draw(in: CGRect(x: bounds.midX - 230, y: bounds.midY - 45, width: 460, height: 30), withAttributes: attributes)
            "Drag a colored shape from the left to start your quilt.".draw(in: CGRect(x: bounds.midX - 230, y: bounds.midY - 12, width: 460, height: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
        }
        // One nominal inch, rendered at the current zoom.
        let ruler = NSBezierPath(), x: CGFloat = 22, y = bounds.height - 25
        ruler.move(to: CGPoint(x: x, y: y - 5)); ruler.line(to: CGPoint(x: x, y: y)); ruler.line(to: CGPoint(x: x + session.zoom, y: y)); ruler.line(to: CGPoint(x: x + session.zoom, y: y - 5))
        NSColor(hex: "65756B").setStroke(); ruler.lineWidth = 1.5; ruler.stroke()
        "1″".draw(at: CGPoint(x: x, y: y - 24), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(hex: "65756B")])
    }
    func drawGrid() {
        let a = world(.zero), b = world(CGPoint(x: bounds.maxX, y: bounds.maxY))
        let side = 2 / sqrt(3.0)
        let step = session.zoom < 20 ? 8 : session.zoom < 30 ? 4 : session.zoom < 60 ? 2 : 1
        let rMin = Int(floor(a.y * 4)) - 2, rMax = Int(ceil(b.y * 4)) + 2
        let qMin = Int(floor((a.x / side - b.y / 2) * 4)) - 2, qMax = Int(ceil((b.x / side - a.y / 2) * 4)) + 2
        let sMin = Int(floor((a.x / side + a.y / 2) * 4)) - 2, sMax = Int(ceil((b.x / side + b.y / 2) * 4)) + 2
        let minor = NSBezierPath(), major = NSBezierPath()
        func line(_ p: CGPoint, _ q: CGPoint, _ index: Int) {
            let path = index % 4 == 0 ? major : minor
            path.move(to: screen(p)); path.line(to: screen(q))
        }
        for r in rMin...rMax where r % step == 0 { line(CGPoint(x: a.x, y: Double(r) / 4), CGPoint(x: b.x, y: Double(r) / 4), r) }
        for q in qMin...qMax where q % step == 0 { line(CGPoint(x: side * (Double(q) / 4 + a.y / 2), y: a.y), CGPoint(x: side * (Double(q) / 4 + b.y / 2), y: b.y), q) }
        for s in sMin...sMax where s % step == 0 { line(CGPoint(x: side * (Double(s) / 4 - a.y / 2), y: a.y), CGPoint(x: side * (Double(s) / 4 - b.y / 2), y: b.y), s) }
        NSColor(hex: "E5E4DA").setStroke(); minor.lineWidth = 0.5; minor.stroke()
        NSColor(hex: "D5DACE").setStroke(); major.lineWidth = 0.7; major.stroke()
    }
    func drawPiece(_ piece: Piece, selected: Bool, opacity: CGFloat = 1) {
        let p = path(piece)
        NSColor(hex: quilt.fabric(for: piece).hex).withAlphaComponent(opacity).setFill(); p.fill()
        NSColor(hex: "233E35").withAlphaComponent(0.45).setStroke(); p.lineWidth = 1; p.stroke()
        if selected {
            NSColor.white.setStroke(); p.lineWidth = 4; p.stroke()
            NSColor(hex: "244E42").setStroke(); p.lineWidth = 2; p.stroke()
            let anchor = screen(piece.origin.inches)
            NSColor(hex: "244E42").setFill(); NSBezierPath(ovalIn: CGRect(x: anchor.x - 4, y: anchor.y - 4, width: 8, height: 8)).fill()
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil); startCenter = session.center; didDrag = false
        if session.panMode || spaceDown { NSCursor.closedHand.set(); return }
        moving = quilt.pieces.reversed().first { path($0).contains(start) }
        session.selection = moving?.id
    }
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard hypot(location.x - start.x, location.y - start.y) > 3 else { return }
        didDrag = true
        if session.panMode || spaceDown || moving == nil {
            session.center = CGPoint(x: startCenter.x - (location.x - start.x) / session.zoom, y: startCenter.y - (location.y - start.y) / session.zoom)
        } else if var piece = moving {
            let original = piece.origin.inches
            piece.origin = GridPoint.nearest(to: CGPoint(x: original.x + (location.x - start.x) / session.zoom, y: original.y + (location.y - start.y) / session.zoom))
            preview = piece
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let preview, didDrag { place(preview, action: "Move Piece") }
        moving = nil; preview = nil; needsDisplay = true; NSCursor.arrow.set()
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            zoom(by: exp(-event.scrollingDeltaY * 0.015), around: convert(event.locationInWindow, from: nil))
        } else {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            session.center.x -= event.scrollingDeltaX * multiplier / session.zoom
            session.center.y -= event.scrollingDeltaY * multiplier / session.zoom
        }
    }
    override func magnify(with event: NSEvent) { zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil)) }
    func zoom(by factor: CGFloat, around anchor: CGPoint) {
        let before = world(anchor); session.zoom = min(140, max(8, session.zoom * factor))
        let after = world(anchor); session.center.x += before.x - after.x; session.center.y += before.y - after.y
    }
    func fit() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard !quilt.pieces.isEmpty else { session.center = .zero; session.zoom = 38; return }
        let box = quilt.bounds
        session.center = CGPoint(x: box.midX, y: box.midY)
        session.zoom = min(90, max(8, min((bounds.width - 140) / max(box.width, 1), (bounds.height - 140) / max(box.height, 1))))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { spaceDown = true; NSCursor.openHand.set(); return }
        if event.keyCode == 51 || event.keyCode == 117 { deleteAction?(); return }
        if event.keyCode == 53 { moving = nil; preview = nil; session.selection = nil; needsDisplay = true; return }
        if event.charactersIgnoringModifiers?.lowercased() == "f", event.modifierFlags.intersection([.command, .control, .option]).isEmpty { flipAction?(); return }
        if event.charactersIgnoringModifiers?.lowercased() == "r" { rotateAction?(); return }
        if event.charactersIgnoringModifiers?.lowercased() == "d", event.modifierFlags.contains(.command) { duplicateAction?(); return }
        super.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { spaceDown = false; NSCursor.arrow.set() } else { super.keyUp(with: event) } }
    override func resignFirstResponder() -> Bool { spaceDown = false; return super.resignFirstResponder() }
    func dropPreview(_ sender: NSDraggingInfo) -> Piece? {
        guard let payload = PieceDrag.parse(sender.draggingPasteboard.string(forType: .string)), quilt.fabrics.contains(where: { $0.id == payload.fabricID }) else { return nil }
        let point = world(convert(sender.draggingLocation, from: nil))
        return Piece(kind: payload.kind, size: payload.size, origin: GridPoint.nearest(to: point), rotation: payload.rotation, fabricID: payload.fabricID, flipped: payload.flipped)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        preview = dropPreview(sender); needsDisplay = true
        return preview.map { quilt.canPlace($0) ? .copy : [] } ?? []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { preview = nil; needsDisplay = true }
    override func draggingEnded(_ sender: NSDraggingInfo) { preview = nil; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { dropPreview(sender).map(quilt.canPlace) ?? false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let piece = dropPreview(sender), quilt.canPlace(piece) else { preview = nil; needsDisplay = true; return false }
        place(piece, action: "Add Piece"); preview = nil; needsDisplay = true; window?.makeFirstResponder(self); return true
    }
    func place(_ piece: Piece, action: String) {
        guard quilt.canPlace(piece) else { session.status = "That space is occupied. Try an open triangle."; NSSound.beep(); return }
        var next = quilt
        if let index = next.pieces.firstIndex(where: { $0.id == piece.id }) { next.pieces[index] = piece } else { next.pieces.append(piece) }
        commit?(next, action); session.selection = piece.id
        session.status = "\(piece.kind.title) snapped to the ¼″ grid."
    }
}
