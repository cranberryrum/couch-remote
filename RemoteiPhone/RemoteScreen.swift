import RemoteKit
import SwiftUI

/// The remote itself, shown while connected (or while reconnecting after a drop).
struct RemoteScreen: View {
    let client: RemoteClient
    let idle: IdleManager
    @Binding var night: Bool

    @Environment(\.theme) private var theme
    @State private var keyboardActive = false
    @State private var showSleepDialog = false

    var body: some View {
        VStack(spacing: 12) {
            StatusBar(client: client, night: $night, keyboardActive: $keyboardActive, showSleepDialog: $showSleepDialog)

            ZStack {
                TrackpadView(client: client, night: theme.night)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                if case .reconnecting = client.phase {
                    ReconnectingOverlay(client: client)
                }
            }

            if keyboardActive {
                KeyboardInputView(client: client, isActive: $keyboardActive, onActivity: idle.noteActivity)
                    .frame(height: 44)
            } else {
                MovieKeysRow(client: client)
                ControlBar(client: client)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .confirmationDialog("Sleep timer", isPresented: $showSleepDialog, titleVisibility: .visible) {
            ForEach(Tuning.sleepTimerMinutes, id: \.self) { minutes in
                Button("Sleep Mac in \(minutes) min") { client.setSleepTimer(minutes: minutes) }
            }
            if client.macStatus?.sleepTimerRemaining != nil {
                Button("Cancel timer", role: .destructive) { client.cancelSleepTimer() }
            }
            Button("Close", role: .cancel) {}
        } message: {
            Text("The timer runs on the Mac, so it still sleeps if this iPhone locks.")
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
                .tint(theme.foreground)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct StatusBar: View {
    let client: RemoteClient
    @Binding var night: Bool
    @Binding var keyboardActive: Bool
    @Binding var showSleepDialog: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 9, height: 9)
            macMenu
            Spacer(minLength: 4)
            sleepButton
            iconButton(keyboardActive ? "keyboard.chevron.compact.down" : "keyboard", label: "Keyboard") {
                keyboardActive.toggle()
            }
            iconButton(night ? "moon.fill" : "moon", label: "Night mode") { night.toggle() }
            if let rtt = client.rttMs {
                Text("\(Int(rtt.rounded())) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondary)
                    .frame(minWidth: 38, alignment: .trailing)
            }
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
            HStack(spacing: 4) {
                Text(macName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(theme.foreground)
            .frame(minHeight: 44)
        }
    }

    private var sleepButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = client.sleepTimerRemaining(at: context.date)
            Button {
                showSleepDialog = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: remaining == nil ? "timer" : "moon.zzz.fill")
                    if let remaining {
                        Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                            .font(.caption.monospacedDigit())
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(remaining == nil ? theme.foreground : theme.accent)
                .padding(.horizontal, remaining == nil ? 0 : 8)
                .frame(minWidth: 40, minHeight: 44)
                .background(remaining == nil ? Color.clear : theme.controlFill, in: Capsule())
            }
            .accessibilityLabel("Sleep timer")
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .frame(width: 40, height: 44)
        }
        .accessibilityLabel(label)
    }
}
