import SwiftUI
import AppKit

private let forest = Color(nsColor: NSColor(hex: "315D55"))
private let paper = Color(nsColor: NSColor(hex: "FBFAF6"))

struct ShapeIcon: Shape {
    var kind: PieceKind
    var rotation: Int = 0
    var flipped = false
    var insetScale: CGFloat = 0.85
    func path(in rect: CGRect) -> Path {
        let points = kind.vertices.map { (flipped ? $0.reflected : $0).rotated(rotation).inches }
        let box = Geometry.bounds(points)
        let scale = min(rect.width / box.width, rect.height / box.height) * insetScale
        return Path { path in
            let p = points.map { CGPoint(x: rect.midX + ($0.x - box.midX) * scale, y: rect.midY + ($0.y - box.midY) * scale) }
            path.move(to: p[0]); for v in p.dropFirst() { path.addLine(to: v) }; path.closeSubpath()
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var document: QuiltDocument
    @StateObject private var session = EditorSession()
    @Environment(\.undoManager) private var undoManager
    @State private var showingSummary = false
    @State private var customColor = Color(nsColor: NSColor(hex: "B57155"))
    @State private var customName = "New fabric"
    @State private var addingFabric = false
    @State private var error: String?
    private var quilt: Quilt { document.quilt }
    private var activeFabric: Fabric { quilt.fabrics.first { $0.id == session.fabricID } ?? quilt.fabrics[0] }
    private var selected: Piece? { quilt.pieces.first { $0.id == session.selection } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                palette.frame(width: 232)
                Divider()
                VStack(spacing: 0) {
                    canvasHeader
                    Divider()
                    QuiltCanvas(document: document, session: session, commit: commit, rotate: rotate, flip: flip, delete: delete, duplicate: duplicate)
                        .overlay(alignment: .topTrailing) { viewportControls.padding(16) }
                    Divider()
                    statusBar
                }
                Divider()
                inspector.frame(width: 250)
            }
        }
        .background(paper)
        .tint(forest)
        .navigationTitle(quilt.title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: rotate) { Label("Rotate 60°", systemImage: "rotate.right") }.help("Rotate selected piece, or the next shape (R)")
                Button(action: flip) { Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }.help("Mirror selected piece, or the next shape (F)")
                Button(action: duplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }.disabled(selected == nil).keyboardShortcut("d", modifiers: .command)
                Button(action: delete) { Label("Delete", systemImage: "trash") }.disabled(selected == nil)
                Divider()
                Button { showingSummary = true } label: { Label("Summary", systemImage: "list.bullet.rectangle") }
            }
        }
        .sheet(isPresented: $showingSummary) { summarySheet }
        .alert("Couldn’t export summary", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .onChange(of: quilt.pieces) { _, pieces in if let id = session.selection, !pieces.contains(where: { $0.id == id }) { session.selection = nil } }
        .onAppear { if !quilt.pieces.isEmpty { session.fitRequest += 1 } }
    }
    private var palette: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("POLY TOOL").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2.8).foregroundStyle(forest)
                    Text("Your shape studio").font(.system(size: 22, weight: .semibold, design: .serif))
                    Text("Build something beautiful,\none piece at a time.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 10) {
                    eyebrow("01  FINISHED SIZE")
                    Picker("Finished height", selection: $session.size) { ForEach(QuiltMeasurements.sizes, id: \.self) { size in Text(QuiltMeasurements.inches(size)).tag(size) } }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity)
                    Text("Nominal \(QuiltMeasurements.inches(session.size + 0.5)) strip").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { eyebrow("02  FABRIC COLOR"); Spacer(); Button { addingFabric.toggle() } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain).help("Add a fabric color") }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(quilt.fabrics) { fabric in
                            Button { session.fabricID = fabric.id } label: {
                                RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: NSColor(hex: fabric.hex)))
                                    .frame(height: 34).overlay { if activeFabric.id == fabric.id { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(fabric.hex == "EEE3CB" ? forest : .white).shadow(radius: 1) } }
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.12)))
                            }.buttonStyle(.plain).help(fabric.name).accessibilityLabel(fabric.name)
                        }
                    }
                    Text(activeFabric.name).font(.system(size: 12, weight: .medium)).foregroundStyle(forest)
                    if addingFabric {
                        TextField("Fabric name", text: $customName).textFieldStyle(.roundedBorder)
                        ColorPicker("Color", selection: $customColor, supportsOpacity: false)
                        Button("Add fabric") {
                            var next = quilt
                            let fabric = Fabric(name: customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New fabric" : customName, hex: NSColor(customColor).rgbHex)
                            next.fabrics.append(fabric); commit(next, "Add Fabric"); session.fabricID = fabric.id; addingFabric = false
                        }.buttonStyle(.bordered)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    eyebrow("03  DRAG A SHAPE")
                    ForEach(PieceKind.allCases) { kind in
                        HStack(spacing: 12) {
                            ShapeIcon(kind: kind, rotation: session.rotation, flipped: session.flipped).fill(Color(nsColor: NSColor(hex: activeFabric.hex))).frame(width: 68, height: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title).font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                                Text(kind.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).font(.system(size: 10))
                        }
                        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(forest.opacity(0.12)))
                        .contentShape(Rectangle())
                        .onDrag {
                            NSItemProvider(object: PieceDrag(kind: kind, size: session.size, rotation: session.rotation, fabricID: activeFabric.id, flipped: session.flipped).text as NSString)
                        } preview: {
                            let bounds = Piece(kind: kind, size: session.size, rotation: session.rotation, fabricID: activeFabric.id, flipped: session.flipped).bounds
                            ShapeIcon(kind: kind, rotation: session.rotation, flipped: session.flipped, insetScale: 1)
                                .fill(Color(nsColor: NSColor(hex: activeFabric.hex)))
                                .frame(width: bounds.width * session.zoom, height: bounds.height * session.zoom)
                        }
                        .accessibilityLabel("Drag \(session.size) inch \(activeFabric.name) \(kind.title)")
                    }
                    HStack {
                        Text("Orientation").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button { session.rotation = (session.rotation + 1) % 6 } label: { Label("\(session.rotation * 60)°", systemImage: "rotate.right").font(.system(size: 12)) }.buttonStyle(.bordered)
                    }
                }
                Toggle("Flip new shapes", isOn: $session.flipped).toggleStyle(.switch).controlSize(.small)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Made for 60° geometry", systemImage: "triangle").font(.system(size: 11, weight: .medium)).foregroundStyle(forest)
                    Text("Full shapes on a shared triangular grid. Edges snap together; pieces stay separate.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }
            }.padding(18)
        }.background(paper)
    }
    private var canvasHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.grid.3x3").foregroundStyle(forest)
            VStack(alignment: .leading, spacing: 3) {
                TextField("Quilt name", text: Binding(get: { quilt.title }, set: { value in var next = quilt; next.title = value; commit(next, "Rename Quilt") }))
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                Text("60° TRIANGLE GRID  /  ¼″ SNAP").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Canvas tool", selection: $session.panMode) { Image(systemName: "cursorarrow").tag(false); Image(systemName: "hand.draw").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 82).help("Select and move, or pan")
        }.padding(.horizontal, 20).padding(.vertical, 14).background(.white.opacity(0.65))
    }
    private var viewportControls: some View {
        HStack(spacing: 10) {
            Button { session.zoom = max(8, session.zoom / 1.2) } label: { Image(systemName: "minus") }.help("Zoom out")
            Text("\(Int(session.zoom / 38 * 100))%").font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 44)
            Button { session.zoom = min(140, session.zoom * 1.2) } label: { Image(systemName: "plus") }.help("Zoom in")
            Divider().frame(height: 16)
            Button { session.fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Fit quilt to view")
            Button { session.showGrid.toggle() } label: { Image(systemName: session.showGrid ? "grid" : "square") }.help("Show or hide grid")
        }.buttonStyle(.plain).padding(11).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.08)))
    }
    private var statusBar: some View {
        HStack {
            Circle().fill(forest).frame(width: 5, height: 5)
            Text(session.status).lineLimit(1)
            Spacer()
            Text("Scroll to pan · Pinch to zoom").foregroundStyle(.secondary)
        }.font(.system(size: 10)).padding(.horizontal, 14).frame(height: 30).background(paper)
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("DESIGN OVERVIEW")
                    Text("The whole quilt").font(.system(size: 21, weight: .semibold, design: .serif))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(quilt.pieces.count)").font(.system(size: 42, weight: .light, design: .rounded)); Text("pieces").foregroundStyle(.secondary) }
                VStack(spacing: 12) {
                    metric("Design width", inches(quilt.bounds.width))
                    metric("Design height", inches(quilt.bounds.height))
                    metric("Fabric colors", "\(Set(quilt.pieces.map(\.fabricID)).count)")
                    metric("1″ triangle units", quilt.triangleUnits.formatted())
                }
                Text("Dimensions use nominal finished geometry and include any gaps.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(2)
                Divider()
                if let selected {
                    VStack(alignment: .leading, spacing: 12) {
                        eyebrow("SELECTED PIECE")
                        HStack { ShapeIcon(kind: selected.kind, rotation: selected.rotation, flipped: selected.flipped).fill(Color(nsColor: NSColor(hex: quilt.fabric(for: selected).hex))).frame(width: 40, height: 36); Text(selected.kind.title).font(.headline) }
                        metric("Finished height", QuiltMeasurements.inches(selected.size))
                        metric("Rotation", "\(selected.rotation * 60)°")
                        metric("Mirrored", selected.flipped ? "Yes" : "No")
                        metric("Fabric", quilt.fabric(for: selected).name)
                        Button { var next = quilt; if let index = next.pieces.firstIndex(where: { $0.id == selected.id }) { next.pieces[index].fabricID = activeFabric.id }; commit(next, "Recolor Piece") } label: { Label("Use \(activeFabric.name)", systemImage: "paintpalette") }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                        HStack { Button("Rotate", action: rotate); Button("Flip", action: flip); Button("Duplicate", action: duplicate) }.buttonStyle(.bordered)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) { eyebrow("PIECE INSPECTOR"); Image(systemName: "cursorarrow.rays").font(.title2).foregroundStyle(forest.opacity(0.7)); Text("Select a piece to rotate, flip, recolor, duplicate, or move it.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    eyebrow("PIECES BY SHAPE")
                    ForEach(PieceKind.allCases) { kind in metric(kind.title, "\(quilt.pieces.filter { $0.kind == kind }.count)") }
                    Button { showingSummary = true } label: { Label("View fabric & piece summary", systemImage: "list.bullet.rectangle") }.buttonStyle(.bordered).controlSize(.small)
                }
                if quilt.pieces.isEmpty {
                    Button {
                        var next = Quilt.star(); next.fabrics = quilt.fabrics
                        // Map the sample's three colors into this document's palette.
                        let source = Quilt.star()
                        for i in next.pieces.indices {
                            let colorIndex = source.fabrics.firstIndex { $0.id == source.pieces[i].fabricID } ?? 0
                            next.pieces[i].fabricID = quilt.fabrics[colorIndex % quilt.fabrics.count].id
                        }
                        commit(next, "Load Example"); session.fitRequest += 1; session.status = "Juniper Star · an editable starting point."
                    } label: { Label("Try a star example", systemImage: "sparkles") }.buttonStyle(.borderedProminent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("AT YOUR FINGERTIPS")
                    Text("R  Rotate\nF  Flip\n⌘D  Duplicate\nDelete  Remove\nSpace + drag  Pan\n⌘Z  Undo\n⌘S  Save quilt").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(6)
                }
            }.padding(20)
        }.background(paper)
    }
    private var summarySheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 4) { eyebrow("FABRIC & PIECE SUMMARY"); Text(quilt.title).font(.system(size: 27, weight: .semibold, design: .serif)) }; Spacer(); Button("Done") { showingSummary = false }.keyboardShortcut(.defaultAction) }
            HStack(spacing: 28) { Label("\(quilt.pieces.count) pieces", systemImage: "square.stack.3d.up"); Text("\(inches(quilt.bounds.width)) × \(inches(quilt.bounds.height))"); Text(String(format: "%.1f sq in of shapes", quilt.area)) }.font(.system(size: 13)).foregroundStyle(forest)
            Table(quilt.summary) {
                TableColumn("Fabric") { row in HStack { Circle().fill(Color(nsColor: NSColor(hex: row.fabric.hex))).frame(width: 12, height: 12); Text(row.fabric.name) } }.width(min: 130, ideal: 170)
                TableColumn("Shape") { Text($0.kind.title) }
                TableColumn("Finished height") { Text(QuiltMeasurements.inches($0.size)) }
                TableColumn("Nominal strip") { Text(QuiltMeasurements.inches($0.size + 0.5)) }
                TableColumn("Count") { Text("\($0.count)").monospacedDigit() }.width(50)
            }.frame(minHeight: 240)
            Text("Strip widths follow the planning convention: finished height + ½″. This is a design inventory, not a cutting or yardage plan. Use the ruler’s instructions for seam allowances, trimmed tips, and cutting dimensions. Area excludes seam allowances and waste.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Text("Saved quilts are readable, versioned JSON.").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("Export summary CSV…", action: exportSummary).buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 780, height: 520).background(paper)
    }
    private func eyebrow(_ title: String) -> some View { Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(forest) }
    private func metric(_ label: String, _ value: String) -> some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium).multilineTextAlignment(.trailing) }.font(.system(size: 12)) }
    private func inches(_ value: CGFloat) -> String { String(format: "%.2f″", value) }
    private func commit(_ next: Quilt, _ action: String) { document.replace(next, undo: undoManager, action: action) }
    private func rotate() {
        guard var piece = selected else { session.rotation = (session.rotation + 1) % 6; return }
        piece.rotation = (piece.rotation + 1) % 6
        guard quilt.canPlace(piece) else { session.status = "Rotation would overlap a piece. Move it to an open space first."; NSSound.beep(); return }
        var next = quilt; next.pieces[next.pieces.firstIndex { $0.id == piece.id }!] = piece; commit(next, "Rotate Piece")
    }
    private func flip() {
        guard var piece = selected else { session.flipped.toggle(); return }
        piece.flipped.toggle()
        guard quilt.canPlace(piece) else {
            session.status = "Flipping would overlap a piece. Move it to an open space first."
            NSSound.beep(); return
        }
        var next = quilt
        next.pieces[next.pieces.firstIndex { $0.id == piece.id }!] = piece
        commit(next, "Flip Piece")
        session.status = "Piece flipped around its anchor."
    }
    private func delete() {

        guard let selected else { return }; var next = quilt; next.pieces.removeAll { $0.id == selected.id }; commit(next, "Delete Piece"); session.selection = nil; session.status = "Piece removed. ⌘Z to undo."
    }
    private func duplicate() {
        guard let selected else { return }
        var copy = selected; copy.id = UUID()
        for radius in 1...100 {
            for q in -radius...radius { for r in -radius...radius where abs(q) == radius || abs(r) == radius {
                copy.origin = GridPoint(selected.origin.q + Double(q) / 2, selected.origin.r + Double(r) / 2)
                if quilt.canPlace(copy) { var next = quilt; next.pieces.append(copy); commit(next, "Duplicate Piece"); session.selection = copy.id; session.status = "Duplicate placed in a nearby open space."; return }
            } }
        }
        session.status = "No open space nearby for a duplicate."
    }
    private func exportSummary() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = "\(quilt.title) - Summary.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func escaped(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["Fabric,Color,Shape,Nominal finished height (in),Nominal strip width (in),Count"]
        lines += quilt.summary.map { "\(escaped($0.fabric.name)),#\($0.fabric.hex),\($0.kind.title),\($0.size),\(Double($0.size) + 0.5),\($0.count)" }
        do { try (lines.joined(separator: "\r\n") + "\r\n").write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
    }
}
