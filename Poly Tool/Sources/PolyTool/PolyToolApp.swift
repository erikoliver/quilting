import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let polyQuilt = UTType(exportedAs: "com.richardsonoliver.polytool.quilt", conformingTo: .json)
}

final class QuiltDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.polyQuilt, .json] }
    static var writableContentTypes: [UTType] { [.polyQuilt, .json] }
    @Published var quilt: Quilt
    init(quilt: Quilt = Quilt()) { self.quilt = quilt }
    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        quilt = try Quilt.decoded(data)
    }
    func snapshot(contentType: UTType) throws -> Data { try quilt.encoded() }
    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: snapshot) }
    func replace(_ next: Quilt, undo: UndoManager?, action: String) {
        let previous = quilt
        guard previous != next else { return }
        undo?.registerUndo(withTarget: self) { target in target.replace(previous, undo: undo, action: action) }
        undo?.setActionName(action)
        quilt = next
    }
}

@main
struct PolyToolApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { QuiltDocument() }) { file in
            WorkspaceView(document: file.document)
                .frame(minWidth: 1050, minHeight: 680)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1360, height: 860)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var rgbHex: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

@MainActor final class EditorSession: ObservableObject {
    @Published var selection: UUID?
    @Published var fabricID: UUID?
    @Published var size = 2.0
    @Published var rotation = 0
    @Published var flipped = false
    @Published var panMode = false
    @Published var showGrid = true
    @Published var zoom: CGFloat = 38
    @Published var center = CGPoint.zero
    @Published var status = "Drag a shape onto the grid to begin."
    @Published var fitRequest = 0
}
