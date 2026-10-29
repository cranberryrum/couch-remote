import RemoteKit
import SwiftUI

struct ControlBar: View {
    let client: RemoteClient

    var body: some View {
        HStack(spacing: 10) {
            barButton("gobackward", label: "Seek back") { client.send(.key(.arrowLeft)) }
            barButton("playpause.fill", label: "Play or pause") { client.send(.media(.playPause)) }
            barButton("goforward", label: "Seek forward") { client.send(.key(.arrowRight)) }
            barButton("speaker.wave.1.fill", label: "Volume down") { client.send(.media(.volumeDown)) }
            barButton("speaker.wave.3.fill", label: "Volume up") { client.send(.media(.volumeUp)) }
        }
    }

    private func barButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(BarButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.white.opacity(configuration.isPressed ? 0.24 : 0.09),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
