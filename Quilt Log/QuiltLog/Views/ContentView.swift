// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if os(macOS)
import AppKit
#else
import OSLog
import UIKit
#endif

extension Notification.Name {
    static let focusQuiltSearch = Notification.Name("focusQuiltSearch")
}

struct ContentView: View {
    @EnvironmentObject private var store: QuiltStore
    @EnvironmentObject private var preferences: UserPreferences
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @State private var selectedQuiltID: Int64?
    @State private var showingDeleteConfirmation = false
    @State private var showingPDFExport = false
    @State private var searchFocusRequest = 0
    @State private var displayMode: DisplayMode = .list
    @State private var sortOrder: QuiltSortOrder = .oldestFirst
    @State private var groupingMode: QuiltGroupingMode = .status
    @State private var availabilityFilter: QuiltAvailabilityFilter = .all
#if os(iOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var pdfShareItem: PDFShareItem?
    @State private var iPhoneDetailQuiltID: Int64?
#endif

    private var selectedQuilt: Quilt? {
        if let selectedQuiltID, let quilt = visibleQuilts.first(where: { $0.id == selectedQuiltID }) {
            return quilt
        }
#if os(iOS)
        if horizontalSizeClass == .compact {
            return nil
        }
#endif
        return visibleQuilts.first
    }

    private var visibleQuilts: [Quilt] {
        let filteredByAvailability = store.filteredQuilts.filter { quilt in
            switch availabilityFilter {
            case .all:
                return true
            case .available:
                return !quilt.giftedAlready
            case .gifted:
                return quilt.giftedAlready
            case .status(let status):
                return quilt.status == status.rawValue
            }
        }

        return filteredByAvailability.sorted { first, second in
            switch sortOrder {
            case .oldestFirst:
                return first.sequenceNumber == second.sequenceNumber
                    ? first.quiltName.localizedStandardCompare(second.quiltName) == .orderedAscending
                    : first.sequenceNumber < second.sequenceNumber
            case .newestFirst:
                return first.sequenceNumber == second.sequenceNumber
                    ? first.quiltName.localizedStandardCompare(second.quiltName) == .orderedAscending
                    : first.sequenceNumber > second.sequenceNumber
            }
        }
    }

    private var visibleQuiltGroups: [QuiltGroup] {
        QuiltGroup.groups(for: visibleQuilts, groupingMode: groupingMode, sortOrder: sortOrder)
    }

    var body: some View {
        platformSplitView
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
            .onChange(of: visibleQuilts) { _, quilts in
                if let selectedQuiltID, !quilts.contains(where: { $0.id == selectedQuiltID }) {
                    self.selectedQuiltID = nil
                } else if selectedQuiltID == nil, shouldAutoSelectFirstQuilt {
                    selectedQuiltID = quilts.first?.id
                }
            }
            .onAppear {
                displayMode = DisplayMode(rawValue: preferences.contentDisplayMode) ?? .list
                sortOrder = QuiltSortOrder(rawValue: preferences.contentSortOrder) ?? .oldestFirst
                groupingMode = QuiltGroupingMode(rawValue: preferences.contentGroupingMode) ?? .status
                availabilityFilter = QuiltAvailabilityFilter(preferenceValue: preferences.contentAvailabilityFilter)
            }
            .onChange(of: displayMode) { _, mode in
                preferences.contentDisplayMode = mode.rawValue
            }
            .onChange(of: sortOrder) { _, order in
                preferences.contentSortOrder = order.rawValue
            }
            .onChange(of: groupingMode) { _, mode in
                preferences.contentGroupingMode = mode.rawValue
            }
            .onChange(of: availabilityFilter) { _, filter in
                preferences.contentAvailabilityFilter = filter.preferenceValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusQuiltSearch)) { _ in
                searchFocusRequest += 1
            }
    }

    @ViewBuilder
    private var platformSplitView: some View {
#if os(iOS)
        if horizontalSizeClass == .compact {
            iPhoneGalleryExperience
                .overlay(alignment: .topTrailing) {
                    iPhoneCommandMenu
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                }
                .sheet(item: $pdfShareItem) { item in
                    PDFActivityView(activityItems: [item.url])
                }
        } else {
            baseSplitView
                .safeAreaInset(edge: .top, spacing: 0) {
                    iPadCommandBar
                }
                .sheet(item: $pdfShareItem) { item in
                    PDFActivityView(activityItems: [item.url])
                }
            }
#else
        baseSplitView
            .toolbar {
                macToolbar
            }
            .sheet(isPresented: $showingPDFExport) {
                PDFExportSheet()
                    .environmentObject(store)
            }
#endif
    }

#if os(iOS)
    private var iPhoneGalleryExperience: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QuiltGalleryView(
                    quiltGroups: visibleQuiltGroups,
                    visibleCount: visibleQuilts.count,
                    selectedQuiltID: $selectedQuiltID,
                    displayMode: .constant(.gallery),
                    selectedQuilt: selectedQuilt,
                    hideRecipients: $preferences.hideRecipientsOnScreen,
                    bottomContentInset: 88,
                    showsInspectorButton: false,
                    opensDetailsOnTap: true
                ) { quilt in
                    selectedQuiltID = quilt.id
                    iPhoneDetailQuiltID = quilt.id
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)

#if DEBUG && targetEnvironment(simulator)
                if visibleQuilts.isEmpty {
                    sampleDataButton
                        .padding(.bottom, 92)
                }
#endif

                searchField
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
            }
            .navigationDestination(isPresented: Binding(
                get: { iPhoneDetailQuiltID != nil },
                set: { if !$0 { iPhoneDetailQuiltID = nil } }
            )) {
                if let quilt = store.quilts.first(where: { $0.id == iPhoneDetailQuiltID }) {
                    QuiltDetailView(quilt: quilt)
                } else {
                    ContentUnavailableView("No Quilt Selected", systemImage: "square.grid.2x2")
                }
            }
        }
    }
#endif

    @ViewBuilder
    private var baseSplitView: some View {
#if os(iOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            detailContent
        }
#else
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
#endif
    }

#if os(macOS)
    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
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
                sortOrder.toggle()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel(sortOrder.title)
            .help(sortOrder.helpText)

            Picker("Group", selection: $groupingMode) {
                ForEach(QuiltGroupingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 115)
            .help("Group quilts")

            Picker("Show", selection: $availabilityFilter) {
                ForEach(QuiltAvailabilityFilter.allOptions) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 155)
            .help("Filter quilts")
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
#endif

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            searchField
            ZStack {
                List(selection: $selectedQuiltID) {
                    ForEach(visibleQuiltGroups) { group in
                        Section(group.title) {
                            ForEach(group.quilts) { quilt in
                                QuiltRow(
                                    quilt: quilt,
                                    hideRecipient: preferences.hideRecipientsOnScreen
                                )
                                    .tag(quilt.id)
                            }
                        }
                    }
                }
                if visibleQuilts.isEmpty, isInitialCloudSyncActive {
                    InitialCloudSyncView(
                        message: store.cloudSyncStatus.message,
                        sampleDataAction: sampleDataAction
                    )
                        .padding(20)
                }
            }
            syncStatusFooter
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
    }

    @ViewBuilder
    private var detailContent: some View {
        if displayMode == .gallery {
            QuiltGalleryView(
                quiltGroups: visibleQuiltGroups,
                visibleCount: visibleQuilts.count,
                selectedQuiltID: $selectedQuiltID,
                displayMode: $displayMode,
                selectedQuilt: selectedQuilt,
                hideRecipients: $preferences.hideRecipientsOnScreen
            )
        } else if let quilt = selectedQuilt {
            QuiltDetailView(quilt: quilt)
        } else if isInitialCloudSyncActive {
            InitialCloudSyncView(
                message: store.cloudSyncStatus.message,
                sampleDataAction: sampleDataAction
            )
        } else {
            VStack(spacing: 12) {
                ContentUnavailableView("No Quilt Selected", systemImage: "square.grid.2x2")
                sampleDataButton
            }
        }
    }

#if os(iOS)
    private var iPadCommandBar: some View {
        HStack(spacing: 10) {
            Button {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            } label: {
                Image(systemName: "sidebar.left")
            }
            .accessibilityLabel(columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar")

            Picker("View", selection: $displayMode) {
                Label("List", systemImage: "list.bullet").tag(DisplayMode.list)
                Label("Gallery", systemImage: "square.grid.3x3").tag(DisplayMode.gallery)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Button {
                sortOrder.toggle()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel(sortOrder.title)

            Menu {
                Picker("Group", selection: $groupingMode) {
                    ForEach(QuiltGroupingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "rectangle.3.group")
            }
            .accessibilityLabel("Group Quilts")

            Menu {
                Picker("Show", selection: $availabilityFilter) {
                    ForEach(QuiltAvailabilityFilter.allOptions) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter Quilts")

            Spacer(minLength: 0)

            Menu {
                ForEach(PDFExportPreset.allCases) { preset in
                    Button {
                        sharePDF(preset)
                    } label: {
                        Label(preset.title, systemImage: "doc.richtext")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share PDF")

            Button {
                Task {
                    if let newID = await store.createQuilt() {
                        selectedQuiltID = newID
                        displayMode = .list
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New Quilt")

            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedQuilt == nil)
            .accessibilityLabel("Delete Quilt")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var iPhoneCommandMenu: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    sortOrder.toggle()
                } label: {
                    Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                }
                Picker("Group", selection: $groupingMode) {
                    ForEach(QuiltGroupingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Show", selection: $availabilityFilter) {
                    ForEach(QuiltAvailabilityFilter.allOptions) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Filter and Sort")

            Menu {
                ForEach(PDFExportPreset.allCases) { preset in
                    Button {
                        sharePDF(preset)
                    } label: {
                        Label(preset.title, systemImage: "doc.richtext")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Share PDF")

            Button {
                Task {
                    if let newID = await store.createQuilt() {
                        selectedQuiltID = newID
                        iPhoneDetailQuiltID = newID
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("New Quilt")

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash.circle.fill")
                    .frame(width: 48, height: 48)
            }
            .disabled(selectedQuilt == nil)
            .accessibilityLabel("Delete Quilt")
        }
        .font(.system(size: 28, weight: .regular))
        .symbolRenderingMode(.hierarchical)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private func sharePDF(_ preset: PDFExportPreset) {
        do {
            let url = try store.temporaryPDFExportURL(
                for: preset,
                ownerName: preferences.exportOwnerName
            )
            pdfShareItem = PDFShareItem(url: url)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
#endif

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

    private var syncStatusFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: store.cloudSyncStatus.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.cloudSyncStatus.phase == .failed ? .red : .secondary)
                .frame(width: 16)
            Text(store.cloudSyncStatus.message)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .help(syncStatusHelp)
    }

    private var syncStatusHelp: String {
        guard let date = store.cloudSyncStatus.lastUpdated else {
            return store.cloudSyncStatus.message
        }
        return "\(store.cloudSyncStatus.message) at \(date.formatted(date: .abbreviated, time: .standard))"
    }

    private var isInitialCloudSyncActive: Bool {
        guard store.quilts.isEmpty else { return false }
        switch store.cloudSyncStatus.phase {
        case .settingUp, .importing:
            return true
        case .waiting, .exporting, .idle, .failed:
            return false
        }
    }

    private var shouldAutoSelectFirstQuilt: Bool {
#if os(iOS)
        horizontalSizeClass != .compact
#else
        true
#endif
    }

    private var sampleDataAction: (() -> Void)? {
#if DEBUG && targetEnvironment(simulator)
        {
            Task {
                await store.importBundledSampleData()
            }
        }
#else
        nil
#endif
    }

    @ViewBuilder
    private var sampleDataButton: some View {
#if DEBUG && targetEnvironment(simulator)
        Button {
            Task {
                await store.importBundledSampleData()
            }
        } label: {
            Label("Load Sample Data", systemImage: "tray.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
#endif
    }
}

private struct InitialCloudSyncView: View {
    let message: String
    var sampleDataAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Syncing your quilt library")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let sampleDataAction {
                Button {
                    sampleDataAction()
                } label: {
                    Label("Load Sample Data", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(iOS)
private struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PDFActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

private struct SearchTextField: View {
#if os(iOS)
    private static let keyboardLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "QuiltLog", category: "Keyboard")
#endif
    let placeholder: String
    @Binding var text: String
    @Binding var focusRequest: Int
#if os(iOS)
    @FocusState private var isFocused: Bool
    @State private var draftText = ""
    @State private var searchCommitTask: Task<Void, Never>?
    @State private var focusStartedAt: Date?
#endif

    var body: some View {
#if os(macOS)
        MacSearchTextField(
            placeholder: placeholder,
            text: $text,
            focusRequest: $focusRequest
        )
#else
        HStack(spacing: 6) {
            TextField(placeholder, text: $draftText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onTapGesture {
                    focusStartedAt = Date()
                    Self.keyboardLogger.info("Search tap")
                }
                .onSubmit {
                    commitSearchImmediately()
                    isFocused = false
                }

            if !draftText.isEmpty {
                Button {
                    draftText = ""
                    commitSearchImmediately()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
            .onAppear {
                draftText = text
            }
            .onDisappear {
                searchCommitTask?.cancel()
            }
            .onChange(of: draftText) { _, value in
                scheduleSearchCommit(value)
            }
            .onChange(of: text) { _, value in
                if value != draftText {
                    draftText = value
                }
            }
            .onChange(of: focusRequest) { _, _ in
                focusStartedAt = Date()
                Self.keyboardLogger.info("Search focus requested")
                isFocused = true
            }
            .onChange(of: isFocused) { _, focused in
                if let focusStartedAt {
                    Self.keyboardLogger.info("Search focus=\(focused, privacy: .public) after \(Date().timeIntervalSince(focusStartedAt), privacy: .public)s")
                } else {
                    Self.keyboardLogger.info("Search focus=\(focused, privacy: .public)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if let focusStartedAt {
                    Self.keyboardLogger.info("keyboardWillShow after \(Date().timeIntervalSince(focusStartedAt), privacy: .public)s")
                } else {
                    Self.keyboardLogger.info("keyboardWillShow")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                if let focusStartedAt {
                    Self.keyboardLogger.info("keyboardDidShow after \(Date().timeIntervalSince(focusStartedAt), privacy: .public)s")
                } else {
                    Self.keyboardLogger.info("keyboardDidShow")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                Self.keyboardLogger.info("keyboardWillHide")
            }
#endif
    }

#if os(iOS)
    private func scheduleSearchCommit(_ value: String) {
        searchCommitTask?.cancel()
        searchCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            text = value
        }
    }

    private func commitSearchImmediately() {
        searchCommitTask?.cancel()
        text = draftText
    }
#endif
}

#if os(macOS)
private struct MacSearchTextField: NSViewRepresentable {
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
#endif

private struct QuiltRow: View {
    let quilt: Quilt
    let hideRecipient: Bool

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
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if !hideRecipient, !quilt.recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return quilt.recipient
        }
        return quilt.approxSize
    }
}

private enum DisplayMode: String {
    case list
    case gallery
}

private enum QuiltSortOrder: String, CaseIterable, Identifiable {
    case oldestFirst
    case newestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oldestFirst:
            return "Oldest First"
        case .newestFirst:
            return "Newest First"
        }
    }

    var helpText: String {
        switch self {
        case .oldestFirst:
            return "Sorted oldest first. Click to sort newest first."
        case .newestFirst:
            return "Sorted newest first. Click to sort oldest first."
        }
    }

    mutating func toggle() {
        self = self == .oldestFirst ? .newestFirst : .oldestFirst
    }
}

private enum QuiltGroupingMode: String, CaseIterable, Identifiable {
    case status
    case availability
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status:
            return "By Status"
        case .availability:
            return "By Gifted"
        case .none:
            return "No Groups"
        }
    }
}

private enum QuiltAvailabilityFilter: Hashable, Identifiable {
    case all
    case available
    case gifted
    case status(QuiltStatus)

    static var allOptions: [QuiltAvailabilityFilter] {
        [.all, .available, .gifted] + QuiltStatus.allCases.map { .status($0) }
    }

    var id: String {
        switch self {
        case .all:
            return "all"
        case .available:
            return "available"
        case .gifted:
            return "gifted"
        case .status(let status):
            return "status-\(status.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .available:
            return "Available"
        case .gifted:
            return "Gifted"
        case .status(let status):
            return status.rawValue
        }
    }

    var preferenceValue: String {
        switch self {
        case .all:
            return "all"
        case .available:
            return "available"
        case .gifted:
            return "gifted"
        case .status(let status):
            return "status:\(status.rawValue)"
        }
    }

    init(preferenceValue: String) {
        switch preferenceValue {
        case "available":
            self = .available
        case "gifted":
            self = .gifted
        default:
            if preferenceValue.hasPrefix("status:") {
                let rawStatus = String(preferenceValue.dropFirst("status:".count))
                if let status = QuiltStatus(rawValue: rawStatus) {
                    self = .status(status)
                    return
                }
            }
            self = .all
        }
    }
}

private struct QuiltGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let quilts: [Quilt]

    static func groups(for quilts: [Quilt], groupingMode: QuiltGroupingMode, sortOrder: QuiltSortOrder) -> [QuiltGroup] {
        switch groupingMode {
        case .none:
            return [QuiltGroup(id: "all", title: "All Quilts", quilts: quilts)]
        case .availability:
            return [
                QuiltGroup(id: "available", title: "Available", quilts: quilts.filter { !$0.giftedAlready }),
                QuiltGroup(id: "gifted", title: "Gifted", quilts: quilts.filter(\.giftedAlready))
            ].filter { !$0.quilts.isEmpty }
        case .status:
            let knownStatuses = Set(QuiltStatus.allCases.map(\.rawValue))
            let statuses = sortOrder == .newestFirst
                ? QuiltStatus.allCases.reversed()
                : QuiltStatus.allCases
            var groups = statuses.compactMap { status -> QuiltGroup? in
                let matchingQuilts = quilts.filter { $0.status == status.rawValue }
                guard !matchingQuilts.isEmpty else { return nil }
                return QuiltGroup(id: status.rawValue, title: status.rawValue, quilts: matchingQuilts)
            }
            let otherQuilts = quilts.filter { !knownStatuses.contains($0.status) }
            if !otherQuilts.isEmpty {
                groups.append(QuiltGroup(id: "other", title: "Other", quilts: otherQuilts))
            }
            return groups
        }
    }
}

private struct QuiltGalleryView: View {
    @EnvironmentObject private var store: QuiltStore
    let quiltGroups: [QuiltGroup]
    let visibleCount: Int
    @Binding var selectedQuiltID: Int64?
    @Binding var displayMode: DisplayMode
    let selectedQuilt: Quilt?
    @Binding var hideRecipients: Bool
    var bottomContentInset: CGFloat = 20
    var showsInspectorButton = true
    var opensDetailsOnTap = false
    var openDetails: (Quilt) -> Void = { _ in }
#if os(iOS)
    @State private var showingInspector = false
#endif

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14)
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                galleryHeader

                if visibleCount == 0 {
                    ContentUnavailableView("No Quilts", systemImage: "square.grid.3x3")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(quiltGroups) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(group.title)
                                        .font(.headline)
                                        .padding(.horizontal, 20)

                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                                        ForEach(group.quilts) { quilt in
                                            QuiltCoverTile(
                                                quilt: quilt,
                                                coverPhoto: coverPhoto(for: quilt),
                                                isSelected: selectedQuiltID == quilt.id,
                                                hideRecipient: hideRecipients
                                            ) {
                                                selectedQuiltID = quilt.id
                                                if opensDetailsOnTap {
                                                    openDetails(quilt)
                                                }
                                            } doubleClickAction: {
                                                selectedQuiltID = quilt.id
                                                if opensDetailsOnTap {
                                                    openDetails(quilt)
                                                } else {
                                                    displayMode = .list
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.bottom, bottomContentInset)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

#if os(macOS)
            Divider()

            GalleryInspector(
                quilt: selectedQuilt,
                coverPhoto: selectedQuilt.flatMap(coverPhoto(for:)),
                displayMode: $displayMode,
                hideRecipient: hideRecipients,
                onEditDetails: {}
            )
            .frame(width: 320)
#endif
        }
#if os(iOS)
        .sheet(isPresented: $showingInspector) {
            GalleryInspector(
                quilt: selectedQuilt,
                coverPhoto: selectedQuilt.flatMap(coverPhoto(for:)),
                displayMode: $displayMode,
                hideRecipient: hideRecipients,
                onEditDetails: { showingInspector = false }
            )
        }
#endif
    }

    private var galleryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gallery")
                    .font(.title2.bold())
#if os(iOS)
                    .onTapGesture(count: 2) {
                        hideRecipients.toggle()
                    }
                    .accessibilityHint(hideRecipients ? "Double tap to show recipients" : "Double tap to hide recipients")
#endif
                Text("\(visibleCount) quilts")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
#if os(iOS)
            if showsInspectorButton {
                Button {
                    showingInspector = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.bordered)
                .disabled(selectedQuilt == nil)
                .accessibilityLabel("Show Quilt Details")
            }
#endif
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
    let hideRecipient: Bool
    let action: () -> Void
    let doubleClickAction: () -> Void

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
                    .stroke(isSelected ? Color.accentColor : .quiltSeparator, lineWidth: isSelected ? 2.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { doubleClickAction() }
        )
    }

    private var coverImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.quiltQuaternaryLabel.opacity(0.2))

            if let data = coverPhoto?.thumbnailData, let image = PlatformImage(data: data) {
                Image(platformImage: image)
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
        isSelected ? Color.accentColor.opacity(0.08) : .quiltControlBackground
    }

    private var statusColor: Color {
        quilt.giftedAlready ? .secondary : .green
    }

    private var tileSubtitle: String {
        if !hideRecipient, !quilt.recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
    let hideRecipient: Bool
    let onEditDetails: () -> Void

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
                    metadata("Started", quilt.startedDate)
                    metadata("Piecing Completed", quilt.quiltDate)
                    metadata("Quilting Completed", quilt.quiltingCompletedDate)
                    metadata("Designer", quilt.designerName)
                    metadata("Pattern", quilt.patternName)
                    metadata("Fabric Store", quilt.fabricStore)
                    metadata("Fabric Line", quilt.fabricLine)
                    metadata("Fabric", quilt.fabricReminder)
                    metadata("Quilter", quilt.quilterName)
                    metadata("Quilting Pattern", quilt.quiltingPatternName)
                    if !hideRecipient {
                        metadata("Recipient", quilt.recipient)
                    }

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
                        onEditDetails()
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
                .fill(Color.quiltQuaternaryLabel.opacity(0.2))

            if let data = coverPhoto?.thumbnailData, let image = PlatformImage(data: data) {
                Image(platformImage: image)
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
