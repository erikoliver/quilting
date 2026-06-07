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
            if let quilt = selectedQuilt {
                QuiltDetailView(quilt: quilt)
            } else {
                ContentUnavailableView("No Quilt Selected", systemImage: "square.grid.2x2")
            }
        }
        .toolbar {
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
