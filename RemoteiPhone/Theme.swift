import SwiftUI
import UIKit

/// Day vs. night palette. Night mode is true black with dim, warm accents (no bright green/orange)
/// so the phone doesn't light up the room.
struct Theme: Equatable {
    var night = false

    var background: Color { .black }
    var surface: Color { Color(uiColor: surfaceUIColor) }
    var surfaceUIColor: UIColor { UIColor(white: night ? 0 : 0.09, alpha: 1) }
    var sheetBackground: Color { Color(white: night ? 0.025 : 0.075) }
    var border: Color { Color.white.opacity(night ? 0.05 : 0.08) }

    var controlFill: Color { Color.white.opacity(night ? 0.05 : 0.09) }
    var controlFillProminent: Color { Color.white.opacity(night ? 0.09 : 0.15) }
    var controlFillPressed: Color { Color.white.opacity(night ? 0.14 : 0.26) }
    /// Icon / label color on controls.
    var foreground: Color { night ? Color(red: 0.62, green: 0.45, blue: 0.30) : .white }
    var secondary: Color { night ? Color(red: 0.45, green: 0.33, blue: 0.22) : Color.white.opacity(0.45) }

    var good: Color { night ? Color(red: 0.70, green: 0.45, blue: 0.18) : .green }
    var pending: Color { night ? Color(red: 0.45, green: 0.30, blue: 0.14) : .orange }
    var bad: Color { night ? Color(red: 0.50, green: 0.18, blue: 0.14) : .red }
    var accent: Color { night ? Color(red: 0.70, green: 0.45, blue: 0.18) : .white }
}

/// One small scale of continuous corner radii, so nothing is rounded "by eye".
enum Radius {
    /// Small chips and inline buttons.
    static let chip: CGFloat = 12
    /// Buttons and tiles.
    static let control: CGFloat = 18
    /// Cards, list rows, banners.
    static let card: CGFloat = 22
    /// Big surfaces: the trackpad, sheets.
    static let surface: CGFloat = 28
}

/// Motion. UI animation is short and uses a strong ease-out (cubic-bezier(0.23, 1, 0.32, 1)): it
/// starts moving instantly, which is what makes an interface feel responsive. Nothing here uses
/// ease-in, nothing is longer than ~220 ms, and anything pressed many times a day only gets
/// press feedback, no decorative motion.
enum Motion {
    static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// Press feedback on buttons.
    static let press = easeOut(0.14)
    /// Small state changes (toggling a strip, a chip appearing).
    static let quick = easeOut(0.18)
    /// Crossfades between whole screens, overlays.
    static let standard = easeOut(0.22)

    /// Pressed elements shrink slightly, so the interface visibly "hears" the touch.
    static let pressedScale: CGFloat = 0.97
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
