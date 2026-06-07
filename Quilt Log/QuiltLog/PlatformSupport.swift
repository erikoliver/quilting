// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

#if canImport(UIKit)
import UIKit

typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

extension Color {
    static var quiltControlBackground: Color { Color(uiColor: .secondarySystemBackground) }
    static var quiltQuaternaryLabel: Color { Color(uiColor: .quaternaryLabel) }
    static var quiltSeparator: Color { Color(uiColor: .separator) }
}
#elseif canImport(AppKit)
import AppKit

typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

extension Color {
    static var quiltControlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var quiltQuaternaryLabel: Color { Color(nsColor: .quaternaryLabelColor) }
    static var quiltSeparator: Color { Color(nsColor: .separatorColor) }
}
#endif
