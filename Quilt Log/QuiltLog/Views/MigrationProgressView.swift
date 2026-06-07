// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct MigrationProgressView: View {
    let progress: MigrationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Converting Legacy Quilt Log Library")
                    .font(.headline)
            }

            ProgressView(value: progress.fractionCompleted)

            Text(progress.message)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("\(progress.completed) of \(progress.total) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 420)
    }
}

