// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AboutQuiltLogView: View {
    @EnvironmentObject private var store: QuiltStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("App") {
                    infoRow("Version", store.runtimeInfo.appVersion)
                    infoRow("Build", store.runtimeInfo.buildNumber)
                }

                Section("iCloud") {
                    infoRow("Environment", store.runtimeInfo.cloudKitEnvironment)
                    infoRow("Container", store.runtimeInfo.cloudKitContainerIdentifier)
                    infoRow("Sync Status", store.cloudSyncStatus.message)
                }

                Section("Library") {
                    infoRow("Metadata Schema", metadataSchemaDescription)
                    infoRow("Backup Format", store.runtimeInfo.backupFormatVersion)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("About Quilt Log")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
#if os(macOS)
        .frame(width: 460, height: 360)
#endif
    }

    private var metadataSchemaDescription: String {
        let current = store.runtimeInfo.metadataSchemaVersion
        let expected = store.runtimeInfo.expectedMetadataSchemaVersion
        if current == expected {
            return current
        }
        return "\(current) (expected \(expected))"
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
