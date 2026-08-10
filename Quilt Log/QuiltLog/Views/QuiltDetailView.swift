// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import PhotosUI
import UIKit
#endif

struct QuiltDetailView: View {
    @EnvironmentObject private var store: QuiltStore
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    let quilt: Quilt
    @State private var draft: Quilt
    @State private var lastSavedDraft: Quilt
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var showingPhotoImporter = false
    @State private var selectedPhotoID: Int64?
#if os(iOS)
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var presentedPhoto: QuiltPhoto?
#endif
    @State private var isPhotoDropTargeted = false
    @State private var sequenceConflict: Quilt?
    @State private var displayedDatabaseGeneration: Int?
    @State private var isApplyingSavedDraft = false

    init(quilt: Quilt) {
        self.quilt = quilt
        _draft = State(initialValue: quilt)
        _lastSavedDraft = State(initialValue: quilt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                fields
                photos
                notes
            }
            .padding(detailPadding)
        }
#if os(iOS)
        .sheet(item: $presentedPhoto) { photo in
            NavigationStack {
                PhotoDetailView(photo: photo)
                    .navigationTitle("Photo")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                presentedPhoto = nil
                            }
                        }
                    }
            }
        }
#endif
        .onAppear {
            displayedDatabaseGeneration = store.databaseGeneration
        }
        .task(id: quilt.id) {
            await store.prefetchDisplayImages(around: quilt.id)
        }
        .onChange(of: quilt) { _, newValue in
            if displayedDatabaseGeneration == store.databaseGeneration {
                flushPendingSave()
            } else {
                autoSaveTask?.cancel()
            }
            applySavedDraft(newValue)
            displayedDatabaseGeneration = store.databaseGeneration
        }
        .onChange(of: draft) { _, newValue in
            guard !isApplyingSavedDraft else { return }
            guard newValue != lastSavedDraft else {
                autoSaveTask?.cancel()
                return
            }
#if os(iOS)
            scheduleAutoSave()
#endif
        }
        .onChange(of: draft.status) { _, _ in
            flushPendingSave()
        }
        .onChange(of: draft.giftedAlready) { _, _ in
            flushPendingSave()
        }
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidEndEditingNotification)) { _ in
            flushPendingSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didEndEditingNotification)) { _ in
            flushPendingSave()
        }
#endif
        .onDisappear {
            flushPendingSave()
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
#if os(macOS)
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
#else
        .onChange(of: selectedPhotoItems) { _, items in
            addPhotos(from: items)
        }
#endif
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleBlock
                Spacer()
                revertButton
            }

            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                revertButton
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Quilt Name", text: $draft.quiltName)
                .font(titleFont)
                .textFieldStyle(.plain)
            Text("#\(draft.sequenceNumber)  \(draft.status)")
                .foregroundStyle(.secondary)
        }
    }

    private var revertButton: some View {
        Button {
            revertDraft()
        } label: {
            Label("Revert", systemImage: "arrow.uturn.backward")
        }
        .disabled(draft == lastSavedDraft)
    }

    @ViewBuilder
    private var fields: some View {
        if isCompactWidth {
            VStack(alignment: .leading, spacing: 16) {
                fieldSection("Basics") {
                    VStack(alignment: .leading, spacing: 6) {
                        compactField("Seq #") {
                            TextField("Seq #", value: $draft.sequenceNumber, format: .number)
                        }
                        compactField("Status") {
                            Picker("Status", selection: $draft.status) {
                                ForEach(QuiltStatus.allCases) { status in
                                    Text(status.rawValue).tag(status.rawValue)
                                }
                            }
                        }
                        compactField("Size") {
                            TextField("Approx Size", text: $draft.approxSize)
                        }
                        compactField("Recipient") {
                            TextField("Recipient", text: $draft.recipient)
                        }
                        Toggle("Gifted Already", isOn: $draft.giftedAlready)
                    }
                }

                fieldSection("Dates") {
                    VStack(alignment: .leading, spacing: 6) {
                        compactField("Started") {
                            QuiltDateField("Started", text: $draft.startedDate)
                        }
                        compactField("Piecing Completed") {
                            QuiltDateField("Piecing Completed", text: $draft.quiltDate)
                        }
                        compactField("Quilting Completed") {
                            QuiltDateField("Quilting Completed", text: $draft.quiltingCompletedDate)
                        }
                    }
                }

                fieldSection("Pattern") {
                    VStack(alignment: .leading, spacing: 6) {
                        compactField("Designer") {
                            TextField("Designer", text: $draft.designerName)
                        }
                        compactField("Pattern") {
                            TextField("Pattern Name", text: $draft.patternName)
                        }
                    }
                }

                fieldSection("Fabric") {
                    VStack(alignment: .leading, spacing: 6) {
                        compactField("Store") {
                            TextField("Store", text: $draft.fabricStore)
                        }
                        compactField("Fabric Line") {
                            TextField("Fabric Line", text: $draft.fabricLine)
                        }
                        compactField("Fabric") {
                            TextField("Fabric Reminder", text: $draft.fabricReminder)
                        }
                    }
                }

                fieldSection("Quilting") {
                    VStack(alignment: .leading, spacing: 6) {
                        compactField("Quilter") {
                            TextField("Quilter", text: $draft.quilterName)
                        }
                        compactField("Quilting Pattern") {
                            TextField("Quilting Pattern", text: $draft.quiltingPatternName)
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                fieldSection("Basics") {
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
                            labeled("Size") {
                                TextField("Approx Size", text: $draft.approxSize)
                                    .frame(width: 160)
                            }
                        }
                        GridRow {
                            labeled("Recipient") {
                                TextField("Recipient", text: $draft.recipient)
                                    .frame(minWidth: 260)
                            }
                            labeled("Gifted") {
                                Toggle("Gifted Already", isOn: $draft.giftedAlready)
#if os(macOS)
                                    .toggleStyle(.checkbox)
#endif
                            }
                            Color.clear.frame(width: 1, height: 1)
                        }
                    }
                }

                fieldSection("Dates") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            labeled("Started") {
                                QuiltDateField("Started", text: $draft.startedDate)
                                    .frame(width: 165)
                            }
                            labeled("Piecing Completed") {
                                QuiltDateField("Piecing Completed", text: $draft.quiltDate)
                                    .frame(width: 165)
                            }
                            labeled("Quilting Completed") {
                                QuiltDateField("Quilting Completed", text: $draft.quiltingCompletedDate)
                                    .frame(width: 165)
                            }
                        }
                    }
                }

                fieldSection("Pattern") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            labeled("Designer") {
                                TextField("Designer", text: $draft.designerName)
                                    .frame(minWidth: 260)
                            }
                            labeled("Pattern") {
                                TextField("Pattern Name", text: $draft.patternName)
                                    .frame(minWidth: 360)
                            }
                        }
                    }
                }

                fieldSection("Fabric") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            labeled("Store") {
                                TextField("Store", text: $draft.fabricStore)
                                    .frame(minWidth: 220)
                            }
                            labeled("Fabric Line") {
                                TextField("Fabric Line", text: $draft.fabricLine)
                                    .frame(minWidth: 260)
                            }
                            labeled("Fabric") {
                                TextField("Fabric Reminder", text: $draft.fabricReminder)
                                    .frame(minWidth: 300)
                            }
                        }
                    }
                }

                fieldSection("Quilting") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            labeled("Quilter") {
                                TextField("Quilter", text: $draft.quilterName)
                                    .frame(minWidth: 260)
                            }
                            labeled("Quilting Pattern") {
                                TextField("Quilting Pattern", text: $draft.quiltingPatternName)
                                    .frame(minWidth: 360)
                            }
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos")
                    .font(.headline)
                Spacer()
#if os(macOS)
                Button {
                    pastePhotoFromPasteboard()
                } label: {
                    Label("Paste Photo", systemImage: "doc.on.clipboard")
                }
                .help("Paste a copied image into this quilt")
#elseif os(iOS)
                Button {
                    pastePhotoFromPasteboard()
                } label: {
                    Label("Paste Photo", systemImage: "doc.on.clipboard")
                }
#endif

#if os(macOS)
                Button {
                    showingPhotoImporter = true
                } label: {
                    Label("Add Photos", systemImage: "photo.badge.plus")
                }
#else
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add Photos", systemImage: "photo.badge.plus")
                }
#endif
            }

            let photos = store.photosByQuiltID[draft.id] ?? []
            if photos.isEmpty {
                ContentUnavailableView("No Photos", systemImage: "photo")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                photoBrowser(for: photos)
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

    @ViewBuilder
    private func photoBrowser(for photos: [QuiltPhoto]) -> some View {
#if os(macOS)
        HStack(alignment: .top, spacing: 16) {
            photoGrid(for: photos)
                .frame(minWidth: 320, idealWidth: 520, maxWidth: 620, alignment: .topLeading)

            if let selectedPhoto = selectedPhoto(in: photos) {
                PhotoDetailView(photo: selectedPhoto)
                    .frame(minWidth: 360, maxWidth: .infinity, minHeight: 320, idealHeight: 420)
                    .layoutPriority(1)
            }
        }
#else
        photoGrid(for: photos)
#endif
    }

    private func photoGrid(for photos: [QuiltPhoto]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: photoTileMinimumWidth), spacing: 12)], spacing: 12) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                PhotoTile(
                    photo: photo,
                    isFirst: index == photos.startIndex,
                    isLast: index == photos.index(before: photos.endIndex),
                    isSelected: isSelected(photo, in: photos)
                ) {
#if os(macOS)
                    selectedPhotoID = photo.id
#else
                    presentedPhoto = photo
#endif
                }
            }
        }
    }

    private func selectedPhoto(in photos: [QuiltPhoto]) -> QuiltPhoto? {
        if let selectedPhotoID,
           let selectedPhoto = photos.first(where: { $0.id == selectedPhotoID }) {
            return selectedPhoto
        }
        return photos.first
    }

    private func isSelected(_ photo: QuiltPhoto, in photos: [QuiltPhoto]) -> Bool {
#if os(macOS)
        selectedPhoto(in: photos)?.id == photo.id
#else
        false
#endif
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
                        .stroke(Color.quiltSeparator)
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

    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func compactField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity)
        }
    }

    private var isCompactWidth: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private var detailPadding: CGFloat {
        isCompactWidth ? 16 : 24
    }

    private var titleFont: Font {
        isCompactWidth ? .title2.bold() : .title.bold()
    }

    private var photoTileMinimumWidth: CGFloat {
        isCompactWidth ? 130 : 150
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        let draftToSave = draft
        let databaseGeneration = store.databaseGeneration
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await saveDraftIfNeeded(draftToSave, databaseGeneration: databaseGeneration)
        }
    }

    private func flushPendingSave() {
        autoSaveTask?.cancel()
        guard draft != lastSavedDraft else { return }
        let draftToSave = draft
        let databaseGeneration = store.databaseGeneration
        Task { await saveDraftIfNeeded(draftToSave, databaseGeneration: databaseGeneration) }
    }

    private func saveDraftIfNeeded(_ draftToSave: Quilt, databaseGeneration: Int) async {
        guard store.databaseGeneration == databaseGeneration else { return }
        guard draftToSave != lastSavedDraft else { return }
        do {
            if let conflict = try store.sequenceConflict(for: draftToSave) {
                if draft.id == draftToSave.id {
                    sequenceConflict = conflict
                }
            } else {
                let didSave = await store.save(draftToSave)
                if didSave, draft.id == draftToSave.id {
                    lastSavedDraft = draftToSave
                }
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func revertDraft() {
        autoSaveTask?.cancel()
        applySavedDraft(lastSavedDraft)
    }

    private func applySavedDraft(_ savedDraft: Quilt) {
        isApplyingSavedDraft = true
        draft = savedDraft
        lastSavedDraft = savedDraft
        isApplyingSavedDraft = false
    }

#if os(macOS)
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
#endif

#if os(iOS)
    private func pastePhotoFromPasteboard() {
        guard let image = UIPasteboard.general.image,
              let data = image.jpegData(compressionQuality: 0.9) else {
            store.errorMessage = "The pasteboard does not contain an image."
            return
        }

        do {
            try store.addPhoto(to: draft, data: data, mimeType: "image/jpeg")
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
#endif

#if os(iOS)
    private func addPhotos(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let quilt = draft
        Task {
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let mimeType = Self.mimeType(for: item.supportedContentTypes.first?.identifier ?? UTType.jpeg.identifier)
                    try await MainActor.run {
                        try store.addPhoto(to: quilt, data: data, mimeType: mimeType)
                    }
                } catch {
                    await MainActor.run {
                        store.errorMessage = error.localizedDescription
                    }
                }
            }
            await MainActor.run {
                selectedPhotoItems = []
            }
        }
    }
#endif

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

#if os(macOS)
    private static func jpegData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
#endif
}

private struct QuiltDateField: View {
    let label: String
    @Binding var text: String
    @State private var showingCalendar = false
    @State private var calendarDate = Date()

    init(_ label: String, text: Binding<String>) {
        self.label = label
        _text = text
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("YYYY-MM-DD", text: $text)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
#endif

            Button {
                calendarDate = Self.date(from: text) ?? Date()
                showingCalendar = true
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Choose \(label) date")
            .popover(isPresented: $showingCalendar) {
                calendarPicker
            }
        }
    }

    private var calendarPicker: some View {
        VStack(spacing: 12) {
            DatePicker(label, selection: $calendarDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

            HStack {
                Button("Clear") {
                    text = ""
                    showingCalendar = false
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingCalendar = false
                }
                Button("Use Date") {
                    text = Self.string(from: calendarDate)
                    showingCalendar = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 320)
    }

    private static func date(from text: String) -> Date? {
        dateFormatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct PhotoDetailView: View {
    @EnvironmentObject private var store: QuiltStore
    let photo: QuiltPhoto
    @State private var image: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !photo.caption.isEmpty {
                Text(photo.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .task(id: photo.id) {
            image = nil
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard !Task.isCancelled else { return }
            image = await store.displayImage(for: photo)
        }
    }

}

private struct PhotoTile: View {
    @EnvironmentObject private var store: QuiltStore
    let photo: QuiltPhoto
    let isFirst: Bool
    let isLast: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    @State private var showingDeleteConfirmation = false
    @State private var thumbnailImage: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                thumbnail
            }
            .buttonStyle(.plain)
            .help("Show larger photo")
            .accessibilityLabel("Show larger photo")

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
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Photo", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete photo")
            }
            .labelStyle(.iconOnly)
        }
        .confirmationDialog(
            "Delete photo?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete Photo", role: .destructive) {
                Task { await store.deletePhoto(photo) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this stored quilt photo.")
        }
        .task(id: photo.id) {
            thumbnailImage = nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            thumbnailImage = await store.thumbnailImage(for: photo)
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
            if let image = thumbnailImage {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(height: 150)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
