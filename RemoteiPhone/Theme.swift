import SwiftUI
import UIKit

/// Day vs. night palette. Night mode is true black with dim, warm accents (no bright green/orange)
/// so the phone doesn't light up the room.
struct Theme: Equatable {
    var night = false

    var background: Color { .black }
    var surface: Color { Color(uiColor: surfaceUIColor) }
    var surfaceUIColor: UIColor { UIColor(white: night ? 0 : 0.09, alpha: 1) }
    var border: Color { Color.white.opacity(night ? 0.05 : 0.08) }

    var controlFill: Color { Color.white.opacity(night ? 0.05 : 0.09) }
    var controlFillPressed: Color { Color.white.opacity(night ? 0.12 : 0.24) }
    /// Icon / label color on controls.
    var foreground: Color { night ? Color(red: 0.62, green: 0.45, blue: 0.30) : .white }
    var secondary: Color { night ? Color(red: 0.45, green: 0.33, blue: 0.22) : Color.white.opacity(0.45) }

    var good: Color { night ? Color(red: 0.70, green: 0.45, blue: 0.18) : .green }
    var pending: Color { night ? Color(red: 0.45, green: 0.30, blue: 0.14) : .orange }
    var bad: Color { night ? Color(red: 0.50, green: 0.18, blue: 0.14) : .red }
    var accent: Color { night ? Color(red: 0.70, green: 0.45, blue: 0.18) : .white }
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
