// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension Notification.Name {
    static let focusQuiltSearch = Notification.Name("focusQuiltSearch")
}

struct ContentView: View {
    @EnvironmentObject private var store: QuiltStore
    @State private var selectedQuiltID: Int64?
    @State private var showingDeleteConfirmation = false
    @State private var showingPDFExport = false
    @State private var searchFocusRequest = 0
    @State private var displayMode: DisplayMode = .list

    private var selectedQuilt: Quilt? {
        if let selectedQuiltID, let quilt = store.quilts.first(where: { $0.id == selectedQuiltID }) {
            return quilt
        }
        return store.quilts.first
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                searchField
                List(selection: $selectedQuiltID) {
                    ForEach(QuiltStatus.allCases) { status in
                        let quilts = store.filteredQuilts.filter { $0.status == status.rawValue }
                        if !quilts.isEmpty {
                            Section(status.rawValue) {
                                ForEach(quilts) { quilt in
                                    QuiltRow(quilt: quilt)
                                        .tag(quilt.id)
                                }
                            }
                        }
                    }

                    let other = store.filteredQuilts.filter { quilt in
                        !QuiltStatus.allCases.map(\.rawValue).contains(quilt.status)
                    }
                    if !other.isEmpty {
                        Section("Other") {
                            ForEach(other) { quilt in
                                QuiltRow(quilt: quilt)
                                    .tag(quilt.id)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            if displayMode == .gallery {
                QuiltGalleryView(
                    selectedQuiltID: $selectedQuiltID,
                    displayMode: $displayMode,
                    selectedQuilt: selectedQuilt
                )
            } else if let quilt = selectedQuilt {
                QuiltDetailView(quilt: quilt)
            } else {
                ContentUnavailableView("No Quilt Selected", systemImage: "square.grid.2x2")
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $displayMode) {
                    Label("List", systemImage: "list.bullet").tag(DisplayMode.list)
                    Label("Gallery", systemImage: "square.grid.3x3").tag(DisplayMode.gallery)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .help("Switch between list detail and visual gallery")
            }

            ToolbarItemGroup {
                Button {
                    Task {
                        if let newID = await store.createQuilt() {
                            selectedQuiltID = newID
                        }
                    }
                } label: {
                    Label("New Quilt", systemImage: "plus")
                }
                .help("Create a new quilt record")

                Button {
                    showingPDFExport = true
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
                .help("Choose a PDF export format")

                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Quilt", systemImage: "trash")
                }
                .help("Delete the selected quilt record")
                .disabled(selectedQuilt == nil)
            }
        }
        .sheet(isPresented: $showingPDFExport) {
            PDFExportSheet()
                .environmentObject(store)
        }
        .alert("Quilt Log", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete quilt?",
            isPresented: $showingDeleteConfirmation,
            presenting: selectedQuilt
        ) { quilt in
            Button("Delete Quilt", role: .destructive) {
                Task {
                    await store.deleteQuilt(id: quilt.id)
                    selectedQuiltID = store.quilts.first?.id
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { quilt in
            Text("This will permanently delete “\(quilt.quiltName)” and its stored photos, then close the sequence-number gap.")
        }
        .onChange(of: store.quilts) { _, quilts in
            if selectedQuiltID == nil || !quilts.contains(where: { $0.id == selectedQuiltID }) {
                selectedQuiltID = quilts.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusQuiltSearch)) { _ in
            searchFocusRequest += 1
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            SearchTextField(
                placeholder: "Search quilts",
                text: $store.searchText,
                focusRequest: $searchFocusRequest
            )
            .frame(height: 22)
        }
        .padding(8)
        .background(.thinMaterial)
    }
}

private struct SearchTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                textField.window?.makeFirstResponder(textField)
                textField.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var lastFocusRequest = 0

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }
    }
}

private struct QuiltRow: View {
    let quilt: Quilt

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(quilt.sequenceNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(quilt.quiltName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(quilt.recipient.isEmpty ? quilt.approxSize : quilt.recipient)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private enum DisplayMode {
    case list
    case gallery
}

private struct QuiltGalleryView: View {
    @EnvironmentObject private var store: QuiltStore
    @Binding var selectedQuiltID: Int64?
    @Binding var displayMode: DisplayMode
    let selectedQuilt: Quilt?

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14)
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                galleryHeader

                if store.filteredQuilts.isEmpty {
                    ContentUnavailableView("No Quilts", systemImage: "square.grid.3x3")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            ForEach(store.filteredQuilts) { quilt in
                                QuiltCoverTile(
                                    quilt: quilt,
                                    coverPhoto: coverPhoto(for: quilt),
                                    isSelected: selectedQuiltID == quilt.id
                                ) {
                                    selectedQuiltID = quilt.id
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            GalleryInspector(
                quilt: selectedQuilt,
                coverPhoto: selectedQuilt.flatMap(coverPhoto(for:)),
                displayMode: $displayMode
            )
            .frame(width: 320)
        }
    }

    private var galleryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gallery")
                    .font(.title2.bold())
                Text("\(store.filteredQuilts.count) quilts")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func coverPhoto(for quilt: Quilt) -> QuiltPhoto? {
        let photos = store.photosByQuiltID[quilt.id] ?? []
        return photos.first(where: \.isCover) ?? photos.first
    }
}

private struct QuiltCoverTile: View {
    let quilt: Quilt
    let coverPhoto: QuiltPhoto?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    coverImage
                        .aspectRatio(1.12, contentMode: .fit)

                    Text(quilt.giftedAlready ? "Gifted" : "Available")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(quilt.sequenceNumber)  \(quilt.quiltName)")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(tileSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(8)
            .background(tileBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var coverImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.2))

            if let data = coverPhoto?.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                    Text("No photo")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var tileBackground: Color {
        isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor)
    }

    private var statusColor: Color {
        quilt.giftedAlready ? .secondary : .green
    }

    private var tileSubtitle: String {
        if !quilt.recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return quilt.recipient
        }
        if !quilt.approxSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return quilt.approxSize
        }
        return quilt.status
    }
}

private struct GalleryInspector: View {
    let quilt: Quilt?
    let coverPhoto: QuiltPhoto?
    @Binding var displayMode: DisplayMode

    var body: some View {
        if let quilt {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inspectorCover

                    VStack(alignment: .leading, spacing: 4) {
                        Text(quilt.quiltName)
                            .font(.title2.bold())
                            .lineLimit(2)
                        Text("#\(quilt.sequenceNumber)")
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    metadata("Status", quilt.status)
                    metadata("Size", quilt.approxSize)
                    metadata("Date", quilt.quiltDate)
                    metadata("Pattern", quilt.patternName)
                    metadata("Fabric", quilt.fabricReminder)
                    metadata("Recipient", quilt.recipient)

                    if !quilt.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(quilt.notes)
                                .font(.callout)
                                .lineLimit(6)
                        }
                    }

                    Button {
                        displayMode = .list
                    } label: {
                        Label("Edit Details", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView("No Quilt Selected", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inspectorCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.2))

            if let data = coverPhoto?.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 36))
                    Text("No cover photo")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.1, contentMode: .fit)
    }

    private func metadata(_ label: String, _ value: String) -> some View {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(trimmedValue.isEmpty ? "-" : trimmedValue)
                .font(.callout)
                .lineLimit(3)
        }
    }
}
