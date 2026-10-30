import RemoteKit
import SwiftUI

// MARK: Main screen: one calm row

/// Play/pause, seek (arrow keys) and volume. Everything else lives in the Controls sheet.
/// These fire on touch-down (not on release) and repeat while held: seeking and volume are
/// "hold to keep going" actions, and acting on touch-down removes a tap's worth of latency.
struct MediaBar: View {
    let client: RemoteClient

    var body: some View {
        HStack(spacing: 10) {
            MediaButton(symbol: "backward.fill", label: "Seek back", repeats: true) { client.send(.key(.arrowLeft)) }
            MediaButton(symbol: "playpause.fill", label: "Play or pause", prominent: true) { client.send(.media(.playPause)) }
            MediaButton(symbol: "forward.fill", label: "Seek forward", repeats: true) { client.send(.key(.arrowRight)) }
            MediaButton(symbol: "speaker.wave.1.fill", label: "Volume down", repeats: true) { client.send(.media(.volumeDown)) }
            MediaButton(symbol: "speaker.wave.3.fill", label: "Volume up", repeats: true) { client.send(.media(.volumeUp)) }
        }
    }
}

struct MediaButton: View {
    let symbol: String
    let label: String
    var prominent = false
    var repeats = false
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        // VoiceOver activates the button's action instead of sending touch-down/up, so route it here.
        Button {
            if UIAccessibility.isVoiceOverRunning { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(PressFireStyle(radius: Radius.control, prominent: prominent, repeats: repeats, fire: action))
        .accessibilityLabel(label)
    }
}

// MARK: Button styles

/// The pressed look shared by every control: a slightly brighter fill and a 3% shrink, 140 ms
/// ease-out. Under Reduce Motion only the fill changes.
struct ControlSurface<Content: View>: View {
    let isPressed: Bool
    var radius: CGFloat = Radius.control
    var prominent = false
    @ViewBuilder var content: Content

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .background(
                isPressed ? theme.controlFillPressed : (prominent ? theme.controlFillProminent : theme.controlFill),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .scaleEffect(isPressed && !reduceMotion ? Motion.pressedScale : 1)
            .animation(Motion.press, value: isPressed)
    }
}

/// A normal tap (acts on release, so a touch that turns into a scroll cancels cleanly).
struct TapStyle: ButtonStyle {
    var radius: CGFloat = Radius.control
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        ControlSurface(isPressed: configuration.isPressed, radius: radius, prominent: prominent) {
            configuration.label
        }
        .onChange(of: configuration.isPressed) { _, pressed in
            if pressed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }
}

/// Fires on touch-down and, if `repeats`, keeps firing while held (after a short delay).
/// Releasing, sliding off, or the touch turning into a scroll all stop it immediately.
struct PressFireStyle: ButtonStyle {
    var radius: CGFloat = Radius.control
    var prominent = false
    var repeats = false
    let fire: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        PressFireBody(configuration: configuration, radius: radius, prominent: prominent, repeats: repeats, fire: fire)
    }
}

private struct PressFireBody: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    let prominent: Bool
    let repeats: Bool
    let fire: () -> Void

    @State private var repeater: Task<Void, Never>?

    var body: some View {
        ControlSurface(isPressed: configuration.isPressed, radius: radius, prominent: prominent) {
            configuration.label
        }
        .onChange(of: configuration.isPressed) { _, pressed in
            stop()
            guard pressed, !UIAccessibility.isVoiceOverRunning else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            fire()
            if repeats { start() }
        }
        .onDisappear { stop() }
    }

    private func start() {
        repeater = Task {
            try? await Task.sleep(for: Tuning.repeatDelay)
            while !Task.isCancelled {
                fire()
                try? await Task.sleep(for: Tuning.repeatInterval)
            }
        }
    }

    private func stop() {
        repeater?.cancel()
        repeater = nil
    }
}

/// Bare icon buttons in the top bar: a soft dim and shrink on press, no background.
struct IconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
