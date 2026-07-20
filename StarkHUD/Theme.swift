//
//  Theme.swift
//  StarkHUD — workshop palette and type.
//

import SwiftUI

enum Theme {
    /// Arc-reactor blue family.
    static let arc       = Color(red: 0.42, green: 0.88, blue: 1.00)
    static let arcBright = Color(red: 0.80, green: 0.98, blue: 1.00)
    static let arcDim    = Color(red: 0.18, green: 0.42, blue: 0.53)

    /// Hot-rod red and gold, used sparingly for accents and alerts.
    static let gold   = Color(red: 1.00, green: 0.76, blue: 0.28)
    static let hotRod = Color(red: 0.95, green: 0.26, blue: 0.16)

    static let bg    = Color(red: 0.010, green: 0.028, blue: 0.048)
    static let panel = Color(red: 0.030, green: 0.095, blue: 0.140).opacity(0.72)

    static func hudFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func labelFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
}

extension View {
    /// Small-caps, tracked-out HUD label treatment.
    func hudLabelStyle(size: CGFloat = 22, color: Color = Theme.arc) -> some View {
        self
            .font(Theme.labelFont(size))
            .kerning(size * 0.16)
            .foregroundStyle(color)
    }
}
