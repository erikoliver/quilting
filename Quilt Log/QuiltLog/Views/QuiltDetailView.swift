// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuiltDetailView: View {
    @EnvironmentObject private var store: QuiltStore
    let quilt: Quilt
    @State private var draft: Quilt
    @State private var showingPhotoImporter = false
    @State private var isPhotoDropTargeted = false
    @State private var sequenceConflict: Quilt?

    init(quilt: Quilt) {
        self.quilt = quilt
        _draft = State(initialValue: quilt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                fields
                photos
                notes
            }
            .padding(24)
        }
        .id(draft.id)
        .onChange(of: quilt) { _, newValue in
            draft = newValue
        }
        .alert("Sequence Number Already Used", isPresented: Binding(
            get: { sequenceConflict != nil },
            set: { if !$0 { sequenceConflict = nil } }
        )) {
            Button("Make Space") {
                Task {
                    await store.saveMakingSpace(for: draft)
                    sequenceConflict = nil
                }
            }
            Button("Cancel", role: .cancel) {
                sequenceConflict = nil
            }
        } message: {
            if let sequenceConflict {
                Text("Seq # \(draft.sequenceNumber) is already used by “\(sequenceConflict.quiltName)”. Make Space will shift the affected quilts so this quilt can use #\(draft.sequenceNumber).")
            }
        }
        .fileImporter(
            isPresented: $showingPhotoImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls {
                    await store.addPhoto(to: draft, from: url)
                }
            }
        }
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            addPhotos(from: providers)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Quilt Name", text: $draft.quiltName)
                    .font(.title.bold())
                    .textFieldStyle(.plain)
                Text("#\(draft.sequenceNumber)  \(draft.status)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await saveDraft() }
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                labeled("Seq #") {
                    TextField("Seq #", value: $draft.sequenceNumber, format: .number)
                        .frame(width: 90)
                }
                labeled("Status") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(QuiltStatus.allCases) { status in
                            Text(status.rawValue).tag(status.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }
                labeled("Date") {
                    TextField("YYYY-MM-DD", text: $draft.quiltDate)
                        .frame(width: 140)
                }
            }
            GridRow {
                labeled("Pattern") {
                    TextField("Pattern Name", text: $draft.patternName)
                }
                labeled("Fabric") {
                    TextField("Fabric Reminder", text: $draft.fabricReminder)
                }
                labeled("Size") {
                    TextField("Approx Size", text: $draft.approxSize)
                        .frame(width: 160)
                }
            }
            GridRow {
                labeled("Recipient") {
                    TextField("Recipient", text: $draft.recipient)
                }
                labeled("Gifted") {
                    Toggle("Gifted Already", isOn: $draft.giftedAlready)
                        .toggleStyle(.checkbox)
                }
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos")
                    .font(.headline)
                Spacer()
                Button {
                    pastePhotoFromPasteboard()
                } label: {
                    Label("Paste Photo", systemImage: "doc.on.clipboard")
                }
                .help("Paste a copied image into this quilt")

                Button {
                    showingPhotoImporter = true
                } label: {
                    Label("Add Photos", systemImage: "photo.badge.plus")
                }
            }

            let photos = store.photosByQuiltID[draft.id] ?? []
            if photos.isEmpty {
                ContentUnavailableView("No Photos", systemImage: "photo")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        PhotoTile(
                            photo: photo,
                            isFirst: index == photos.startIndex,
                            isLast: index == photos.index(before: photos.endIndex)
                        )
                    }
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isPhotoDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPhotoDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .onDrop(
            of: Self.acceptedPhotoTypeIdentifiers,
            isTargeted: $isPhotoDropTargeted
        ) { providers in
            addPhotos(from: providers)
            return true
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            TextEditor(text: $draft.notes)
                .font(.body)
                .frame(minHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func saveDraft() async {
        do {
            if let conflict = try store.sequenceConflict(for: draft) {
                sequenceConflict = conflict
            } else {
                await store.save(draft)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func pastePhotoFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard),
           let data = Self.jpegData(for: image) {
            do {
                try store.addPhoto(to: draft, data: data, mimeType: "image/jpeg")
            } catch {
                store.errorMessage = error.localizedDescription
            }
            return
        }

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        guard !urls.isEmpty else {
            store.errorMessage = "The pasteboard does not contain an image."
            return
        }

        Task {
            for url in urls where Self.isSupportedImageURL(url) {
                await store.addPhoto(to: draft, from: url)
            }
        }
    }

    private func addPhotos(from providers: [NSItemProvider]) {
        let quilt = draft
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let itemURL = item as? URL {
                        url = itemURL
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = nil
                    }

                    guard let url, Self.isSupportedImageURL(url) else { return }
                    Task { @MainActor in
                        await store.addPhoto(to: quilt, from: url)
                    }
                }
                continue
            }

            if let typeIdentifier = Self.acceptedPhotoTypeIdentifiers.first(where: {
                $0 != UTType.fileURL.identifier && provider.hasItemConformingToTypeIdentifier($0)
            }) {
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        do {
                            try store.addPhoto(to: quilt, data: data, mimeType: Self.mimeType(for: typeIdentifier))
                        } catch {
                            store.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private static var acceptedPhotoTypeIdentifiers: [String] {
        [
            UTType.fileURL.identifier,
            UTType.image.identifier,
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.heic.identifier,
            UTType.heif.identifier,
            UTType.tiff.identifier
        ]
    }

    private static func isSupportedImageURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private static func mimeType(for typeIdentifier: String) -> String {
        guard let type = UTType(typeIdentifier) else { return "image/jpeg" }
        if type.conforms(to: .png) { return "image/png" }
        if type.conforms(to: .heic) { return "image/heic" }
        if type.conforms(to: .heif) { return "image/heic" }
        if type.conforms(to: .tiff) { return "image/tiff" }
        return "image/jpeg"
    }

    private static func jpegData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}

private struct PhotoTile: View {
    @EnvironmentObject private var store: QuiltStore
    let photo: QuiltPhoto
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                if let data = photo.thumbnailData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)
            HStack(spacing: 4) {
                Button {
                    Task { await store.setCoverPhoto(photo) }
                } label: {
                    Label("Make Cover", systemImage: photo.isCover ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .help(photo.isCover ? "Cover photo" : "Make this the cover photo")

                Button {
                    Task { await store.movePhoto(photo, by: -1) }
                } label: {
                    Label("Move Earlier", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(isFirst)
                .help("Move earlier")

                Button {
                    Task { await store.movePhoto(photo, by: 1) }
                } label: {
                    Label("Move Later", systemImage: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(isLast)
                .help("Move later")

                Spacer()

                Button(role: .destructive) {
                    Task { await store.deletePhoto(photo) }
                } label: {
                    Label("Delete Photo", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete photo")
            }
            .labelStyle(.iconOnly)
        }
    }
}
