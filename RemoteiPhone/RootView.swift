import SwiftUI

struct RootView: View {
    let client: RemoteClient
    let idle: IdleManager

    @AppStorage("nightMode") private var night = false

    var body: some View {
        Group {
            switch client.phase {
            case .connected, .reconnecting:
                RemoteScreen(client: client, idle: idle, night: $night)
            case .idle, .connecting:
                MyMacsView(client: client, night: $night)
            }
        }
        .environment(\.theme, Theme(night: night))
        .background(Color.black.ignoresSafeArea())
        .background(ActivityMonitor { idle.noteActivity() })
        .preferredColorScheme(.dark)
        .onOpenURL { client.handle(url: $0) }
    }
}
