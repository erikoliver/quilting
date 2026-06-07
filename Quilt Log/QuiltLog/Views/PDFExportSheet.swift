import SwiftUI
import UniformTypeIdentifiers

struct PDFExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: QuiltStore
    @State private var selectedPreset: PDFExportPreset = .completeLog

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export PDF")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                ForEach(PDFExportPreset.allCases) { preset in
                    Button {
                        selectedPreset = preset
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selectedPreset == preset ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selectedPreset == preset ? Color.accentColor : Color.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.title)
                                    .font(.headline)
                                Text(preset.details)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .background(selectedPreset == preset ? Color.accentColor.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Export...") {
                    exportSelectedPreset()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func exportSelectedPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = selectedPreset.defaultFilename

        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportPDF(selectedPreset, to: url)
        dismiss()
    }
}
