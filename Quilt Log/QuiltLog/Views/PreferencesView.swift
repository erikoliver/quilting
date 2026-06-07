// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var preferences: UserPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            privacySection
            exportsSection
        }
        .padding(20)
        .frame(width: 460)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Privacy")
                .font(.headline)

            VStack(spacing: 0) {
                Toggle("Hide recipients on screen", isOn: $preferences.hideRecipientsOnScreen)
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var exportsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exports")
                .font(.headline)

            VStack(spacing: 0) {
                preferenceRow(label: "Name") {
                    TextField("Name", text: $preferences.exportOwnerName)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                preferenceRow(label: "PDF title", secondaryLabel: true) {
                    Text(preferences.exportOwnerNameForDisplay)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                HStack {
                    Button("Use System Name") {
                        preferences.resetExportOwnerNameToSystemUser()
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func preferenceRow<Content: View>(
        label: String,
        secondaryLabel: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .foregroundStyle(secondaryLabel ? .secondary : .primary)
                .frame(width: 110, alignment: .leading)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
