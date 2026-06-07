import SwiftUI
import UniformTypeIdentifiers

struct SQLitePlaceholderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.database] }

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}
