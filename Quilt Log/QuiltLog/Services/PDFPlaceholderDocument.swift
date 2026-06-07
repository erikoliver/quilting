import SwiftUI
import UniformTypeIdentifiers

struct PDFPlaceholderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}
