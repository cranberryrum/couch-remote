import SwiftUI

struct RootView: View {
    let client: RemoteClient
    let idle: IdleManager

    @AppStorage("nightMode") private var night = false

    private var showsRemote: Bool {
        switch client.phase {
        case .connected, .reconnecting: true
        case .idle, .connecting: false
        }
    }

    var body: some View {
        // Connecting / disconnecting happens occasionally, so a short crossfade is welcome.
        ZStack {
            if showsRemote {
                RemoteScreen(client: client, idle: idle, night: $night)
                    .transition(.opacity)
            } else {
                MyMacsView(client: client, night: $night)
                    .transition(.opacity)
            }
        }
        .animation(Motion.standard, value: showsRemote)
        .environment(\.theme, Theme(night: night))
        .background(Color.black.ignoresSafeArea())
        .background(ActivityMonitor { idle.noteActivity() })
        .preferredColorScheme(.dark)
        .onOpenURL { client.handle(url: $0) }
    }
}
