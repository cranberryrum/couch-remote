import RemoteKit
import SwiftUI

/// The second page of controls: everything that isn't needed every minute.
struct ControlsSheet: View {
    let client: RemoteClient
    @Binding var night: Bool

    @Environment(\.theme) private var theme
    @State private var showGetMac = false
    @State private var showAbout = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Controls")
                    .font(.title2.bold())
                    .foregroundStyle(theme.foreground)
                    .padding(.top, 6)

                section("Video and tabs") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ControlTile(symbol: "arrow.up.left.and.arrow.down.right", title: "Fullscreen") { client.send(.key(.f)) }
                        ControlTile(symbol: "speaker.slash.fill", title: "Mute") { client.send(.key(.m)) }
                        ControlTile(symbol: "captions.bubble.fill", title: "Captions") { client.send(.key(.c)) }
                        ControlTile(glyph: "esc", title: "Escape") { client.send(.key(.escape)) }
                        ControlTile(symbol: "chevron.left.square", title: "Previous tab") {
                            client.send(.key(.tab, modifiers: [.control, .shift]))
                        }
                        ControlTile(symbol: "chevron.right.square", title: "Next tab") {
                            client.send(.key(.tab, modifiers: .control))
                        }
                    }
                }

                section("Display", footnote: "Brightness works on the Mac's built-in or an Apple display. You can also pinch on the trackpad to zoom.") {
                    Card {
                        StepRow(symbol: "sun.max", title: "Brightness") {
                            StepButton(symbol: "minus", label: "Brightness down") { client.send(.media(.brightnessDown)) }
                            StepButton(symbol: "plus", label: "Brightness up") { client.send(.media(.brightnessUp)) }
                        }
                        RowDivider()
                        StepRow(symbol: "plus.magnifyingglass", title: "Zoom") {
                            StepButton(symbol: "minus", label: "Zoom out") { client.send(.key(.minus, modifiers: .command)) }
                            ResetButton(label: "Reset zoom") { client.send(.key(.zero, modifiers: .command)) }
                            StepButton(symbol: "plus", label: "Zoom in") { client.send(.key(.equal, modifiers: .command)) }
                        }
                    }
                }

                section("Sleep") {
                    Card {
                        SleepTimerMenu(client: client, showsWhenIdle: true) { remaining in
                            HStack(spacing: 12) {
                                Image(systemName: "moon.zzz")
                                    .frame(width: 24)
                                Text("Sleep timer")
                                Spacer()
                                Text(remaining.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "Off")
                                    .monospacedDigit()
                                    .foregroundStyle(theme.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.footnote)
                                    .foregroundStyle(theme.secondary)
                            }
                            .font(.body)
                            .foregroundStyle(theme.foreground)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                    }
                }

                section("Appearance") {
                    Card {
                        Toggle(isOn: $night) {
                            HStack(spacing: 12) {
                                Image(systemName: "moon")
                                    .frame(width: 24)
                                Text("Night mode")
                            }
                            .foregroundStyle(theme.foreground)
                        }
                        .tint(theme.accent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                    }
                }

                section("Mac app and about") {
                    Card {
                        Button { showGetMac = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.circle")
                                    .frame(width: 24)
                                Text("Get the Mac app")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(theme.secondary)
                            }
                            .font(.body)
                            .foregroundStyle(theme.foreground)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        RowDivider()
                        Button { showAbout = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle")
                                    .frame(width: 24)
                                Text("About the creator")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(theme.secondary)
                            }
                            .font(.body)
                            .foregroundStyle(theme.foreground)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.sheetBackground)
        .getMacAppSheet(isPresented: $showGetMac, theme: theme)
        .aboutSheet(isPresented: $showAbout, theme: theme)
    }

    private func section<Content: View>(
        _ title: String,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(theme.secondary)
                .padding(.leading, 4)
            content()
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: Pieces

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) { content }
            .background(theme.controlFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

struct RowDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: 1)
            .padding(.leading, 52)
    }
}

/// A tile that sends one key on release.
private struct ControlTile: View {
    var symbol: String?
    /// Text shown in place of an icon (for keys that have no good symbol, like "esc").
    var glyph: String?
    let title: String
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                    } else if let glyph {
                        Text(glyph).font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                }
                .font(.system(size: 21, weight: .semibold))
                .frame(height: 24)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(theme.foreground)
            .frame(maxWidth: .infinity, minHeight: 82)
        }
        .buttonStyle(TapStyle(radius: Radius.control))
    }
}

/// An icon, a title, and the stepper buttons on the right.
private struct StepRow<Buttons: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var buttons: Buttons

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
            Text(title)
            Spacer(minLength: 8)
            HStack(spacing: 8) { buttons }
        }
        .font(.body)
        .foregroundStyle(theme.foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
    }
}

/// − / + : fires on touch-down and repeats while held.
private struct StepButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            if UIAccessibility.isVoiceOverRunning { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.foreground)
                .frame(width: 52, height: 44)
        }
        .buttonStyle(PressFireStyle(radius: Radius.chip + 2, prominent: true, repeats: true, fire: action))
        .accessibilityLabel(label)
    }
}

private struct ResetButton: View {
    let label: String
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(TapStyle(radius: Radius.chip + 2, prominent: true))
        .accessibilityLabel(label)
    }
}

/// The sleep-timer picker. Shows a live countdown; `showsWhenIdle` decides whether it is visible
/// while no timer is running (in the sheet) or only while one is (the chip in the top bar).
struct SleepTimerMenu<Label: View>: View {
    let client: RemoteClient
    var showsWhenIdle = false
    @ViewBuilder let label: (Int?) -> Label

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = client.sleepTimerRemaining(at: context.date)
            if remaining != nil || showsWhenIdle {
                Menu {
                    ForEach(Tuning.sleepTimerMinutes, id: \.self) { minutes in
                        Button("Sleep in \(minutes) minutes") { client.setSleepTimer(minutes: minutes) }
                    }
                    if remaining != nil {
                        Divider()
                        Button("Cancel timer", role: .destructive) { client.cancelSleepTimer() }
                    }
                } label: {
                    label(remaining)
                }
                .accessibilityLabel("Sleep timer")
            }
        }
    }
}
