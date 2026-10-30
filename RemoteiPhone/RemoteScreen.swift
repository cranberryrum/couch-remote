import RemoteKit
import SwiftUI

/// The remote itself, shown while connected (or while reconnecting after a drop).
///
/// One calm screen: who you're connected to, the trackpad, and one row of media buttons.
/// Everything else is a swipe-down sheet (the ••• button).
struct RemoteScreen: View {
    let client: RemoteClient
    let idle: IdleManager
    @Binding var night: Bool

    @Environment(\.theme) private var theme
    @State private var keyboardActive = false
    #if DEBUG
    // Test hook: COUCHREMOTE_DEBUG_OPEN_CONTROLS=1 opens the sheet at launch (simulator screenshots).
    @State private var showControls = ProcessInfo.processInfo.environment["COUCHREMOTE_DEBUG_OPEN_CONTROLS"] != nil
    #else
    @State private var showControls = false
    #endif

    private var isReconnecting: Bool {
        if case .reconnecting = client.phase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 14) {
            StatusBar(client: client, keyboardActive: $keyboardActive, showControls: $showControls)

            ZStack {
                TrackpadView(client: client, night: theme.night)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                if isReconnecting {
                    ReconnectingOverlay(client: client)
                        .transition(.opacity)
                }
            }
            .animation(Motion.standard, value: isReconnecting)

            Group {
                if keyboardActive {
                    KeyboardInputView(client: client, isActive: $keyboardActive, onActivity: idle.noteActivity)
                        .frame(height: 44)
                } else {
                    MediaBar(client: client)
                }
            }
            .transition(.opacity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .sheet(isPresented: $showControls) {
            ControlsSheet(client: client, night: $night)
                .environment(\.theme, theme)
                .presentationDetents([.fraction(0.74), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.surface)
                .presentationBackground(theme.sheetBackground)
                .preferredColorScheme(.dark)
        }
    }
}

private struct ReconnectingOverlay: View {
    let client: RemoteClient
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(theme.foreground)
            Text("Reconnecting…")
                .font(.headline)
                .foregroundStyle(theme.foreground)
            Button("Stop") { client.disconnect() }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: Radius.chip))
                .tint(theme.foreground)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
    }
}

private struct StatusBar: View {
    let client: RemoteClient
    @Binding var keyboardActive: Bool
    @Binding var showControls: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 9, height: 9)
                .padding(.trailing, 6)
            macMenu
            Spacer(minLength: 8)
            SleepTimerMenu(client: client) { remaining in
                if let remaining {
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(theme.controlFill, in: Capsule())
                }
            }
            iconButton(keyboardActive ? "keyboard.chevron.compact.down" : "keyboard", label: "Keyboard") {
                // The strip swaps with the media bar a few times a day: a quick fade, nothing more.
                withAnimation(Motion.quick) { keyboardActive.toggle() }
            }
            iconButton("ellipsis.circle", label: "More controls") { showControls = true }
        }
        .padding(.horizontal, 4)
    }

    private var dotColor: Color {
        switch client.phase {
        case .connected: theme.good
        case .connecting, .reconnecting: theme.pending
        case .idle: theme.bad
        }
    }

    private var macName: String {
        if case .reconnecting = client.phase { return "Reconnecting…" }
        return client.activeMac?.displayName ?? "Mac"
    }

    /// The Mac name doubles as a menu: switch to another paired Mac, or disconnect.
    private var macMenu: some View {
        Menu {
            let others = client.pairedMacs.filter { $0.macID != client.activeMac?.macID }
            ForEach(others) { mac in
                Button("Switch to \(mac.displayName)") { client.connect(mac.macID) }
                    .disabled(!client.isOnline(mac.macID))
            }
            if !others.isEmpty { Divider() }
            Button("Disconnect", role: .destructive) { client.disconnect() }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(macName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(theme.foreground)
                if let rtt = client.rttMs {
                    Text("\(Int(rtt.rounded())) ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.secondary)
                }
            }
            .frame(minHeight: 44, alignment: .leading)
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(theme.foreground)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(label)
    }
}
