import RemoteKit
import SwiftUI

/// Play/pause, seek (arrow keys), and volume.
struct ControlBar: View {
    let client: RemoteClient

    var body: some View {
        HStack(spacing: 10) {
            BarButton(symbol: "backward.fill", label: "Seek back") { client.send(.key(.arrowLeft)) }
            BarButton(symbol: "playpause.fill", label: "Play or pause") { client.send(.media(.playPause)) }
            BarButton(symbol: "forward.fill", label: "Seek forward") { client.send(.key(.arrowRight)) }
            BarButton(symbol: "speaker.wave.1.fill", label: "Volume down") { client.send(.media(.volumeDown)) }
            BarButton(symbol: "speaker.wave.3.fill", label: "Volume up") { client.send(.media(.volumeUp)) }
        }
    }
}

/// Fullscreen, mute, captions, Esc, and previous/next browser tab.
struct MovieKeysRow: View {
    let client: RemoteClient

    var body: some View {
        HStack(spacing: 8) {
            BarButton(symbol: "arrow.up.left.and.arrow.down.right", caption: "Fullscreen", label: "Fullscreen", height: 50) {
                client.send(.key(.f))
            }
            BarButton(symbol: "speaker.slash.fill", caption: "Mute", label: "Mute", height: 50) {
                client.send(.key(.m))
            }
            BarButton(symbol: "captions.bubble.fill", caption: "Captions", label: "Captions", height: 50) {
                client.send(.key(.c))
            }
            BarButton(symbol: "escape", caption: "Esc", label: "Escape", height: 50) {
                client.send(.key(.escape))
            }
            BarButton(symbol: "chevron.left.square", caption: "Prev tab", label: "Previous tab", height: 50) {
                client.send(.key(.tab, modifiers: [.control, .shift]))
            }
            BarButton(symbol: "chevron.right.square", caption: "Next tab", label: "Next tab", height: 50) {
                client.send(.key(.tab, modifiers: .control))
            }
        }
    }
}

struct BarButton: View {
    let symbol: String
    var caption: String?
    let label: String
    var height: CGFloat = 58
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: caption == nil ? 20 : 17, weight: .semibold))
                if let caption {
                    Text(caption)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(theme.foreground)
            .frame(maxWidth: .infinity, minHeight: height)
        }
        .buttonStyle(BarButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct BarButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? theme.controlFillPressed : theme.controlFill,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
