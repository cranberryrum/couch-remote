import SwiftUI

struct RootView: View {
    let client: RemoteClient

    var body: some View {
        VStack(spacing: 14) {
            StatusBar(client: client)

            ZStack {
                TrackpadView(client: client)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if client.state == .choosing {
                    MacPicker(client: client)
                } else if !client.isConnected {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(32)
                        .allowsHitTesting(false)
                }
            }

            ControlBar(client: client)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var hint: String {
        client.state == .localNetworkDenied
            ? "Local Network access is off.\nEnable it in Settings › CouchRemote."
            : "Waiting for the CouchRemote app on your Mac…"
    }
}

private struct StatusBar: View {
    let client: RemoteClient

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer()
            if let rtt = client.rttMs {
                Text("\(Int(rtt.rounded())) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 4)
    }

    private var dotColor: Color {
        switch client.state {
        case .connected: .green
        case .connecting, .searching, .choosing: .orange
        case .idle, .localNetworkDenied: .red
        }
    }

    private var title: String {
        switch client.state {
        case .idle: "Idle"
        case .searching: "Searching for Mac…"
        case .choosing: "Choose a Mac"
        case .connecting(let name): "Connecting to \(name)…"
        case .connected(let name): name
        case .localNetworkDenied: "Local Network access denied"
        }
    }
}

private struct MacPicker: View {
    let client: RemoteClient

    var body: some View {
        VStack(spacing: 10) {
            Text("Choose a Mac")
                .font(.headline)
                .foregroundStyle(.white)
            ForEach(client.discovered) { mac in
                Button(mac.name) { client.connect(mac) }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.18))
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
