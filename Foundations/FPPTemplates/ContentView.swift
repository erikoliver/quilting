// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct ContentView: View {
    @AppStorage("selectedShape") private var selectedShapeRawValue = TemplateShape.vblock.rawValue
    @AppStorage("finishedSize") private var finishedSize = 4.0
    @State private var showingDebugGuides = false
    @State private var exportMessage: String?

    private var selectedShape: TemplateShape {
        get {
            let shape = TemplateShape(rawValue: selectedShapeRawValue) ?? .vblock
            return TemplateShape.selectableCases.contains(shape) ? shape : .vblock
        }
        nonmutating set {
            selectedShapeRawValue = newValue.rawValue
        }
    }

    private var clampedFinishedSize: Double {
        min(max((finishedSize * 4).rounded() / 4, 1.0), 7.0)
    }

    private var shapeSelection: Binding<TemplateShape> {
        Binding {
            selectedShape
        } set: { shape in
            selectedShape = shape
        }
    }

    private var finishedSizeSelection: Binding<Double> {
        Binding {
            clampedFinishedSize
        } set: { size in
            finishedSize = min(max((size * 4).rounded() / 4, 1.0), 7.0)
        }
    }

    private var spec: TemplateSpec {
        TemplateSpec(shape: selectedShape, finishedSizeInches: clampedFinishedSize, debug: showingDebugGuides)
    }

    var body: some View {
        HStack(spacing: 0) {
            controls
                .frame(width: 300)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Letter PDF Preview")
                    .font(.headline)

                TemplatePreview(spec: spec)
                    .aspectRatio(8.5 / 11, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .overlay {
                        Rectangle()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            }
            .padding(24)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Foundation Templates")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Generate printable paper piecing PDFs.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Shape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Shape", selection: shapeSelection) {
                    ForEach(TemplateShape.selectableCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Finished Size")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    VStack(spacing: 0) {
                        Button {
                            adjustFinishedSize(by: 0.25)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 36, height: 25)
                        }
                        .buttonStyle(.plain)
                        .disabled(clampedFinishedSize >= 7.0)
                        .accessibilityLabel("Increase finished size")

                        Divider()
                            .frame(width: 28)

                        Button {
                            adjustFinishedSize(by: -0.25)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 36, height: 25)
                        }
                        .buttonStyle(.plain)
                        .disabled(clampedFinishedSize <= 1.0)
                        .accessibilityLabel("Decrease finished size")
                    }
                    .frame(width: 40, height: 56)
                    .background(Color(nsColor: .controlColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("\(formatInches(clampedFinishedSize)) inches")
                        .font(.system(.title3, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Toggle("Show halfway guides", isOn: $showingDebugGuides)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Cut size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(formatInches(spec.outerSizeInches))\" x \(formatInches(spec.outerSizeInches))\"")
                    .font(.system(.title3, design: .monospaced))
            }

            Button {
                exportPDF()
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()
        }
        .padding(24)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(selectedShape.rawValue)-\(formatInches(clampedFinishedSize))in-finished.pdf"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try TemplateRenderer(spec: spec).writePDF(to: url)
            exportMessage = "Wrote \(url.lastPathComponent)"
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func adjustFinishedSize(by amount: Double) {
        finishedSizeSelection.wrappedValue = clampedFinishedSize + amount
    }

    private func formatInches(_ value: Double) -> String {
        let rounded = (value * 4).rounded() / 4
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }
}

private struct TemplatePreview: View {
    let spec: TemplateSpec

    var body: some View {
        Canvas { context, size in
            TemplateRenderer(spec: spec).drawPreview(in: &context, size: size)
        }
        .padding(16)
    }
}
