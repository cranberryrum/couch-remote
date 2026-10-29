import SwiftUI

@main
struct RemoteiPhoneApp: App {
    @State private var client = RemoteClient()
    @State private var idle = IdleManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(client: client, idle: idle)
                .task {
                    #if DEBUG
                    // Test hook (simulator has no camera): pair from a URL given at launch, i.e.
                    // `SIMCTL_CHILD_COUCHREMOTE_DEBUG_PAIR_URL=… xcrun simctl launch …`.
                    // Goes through the same `handle(url:)` as the couchremote:// scheme.
                    if let string = ProcessInfo.processInfo.environment["COUCHREMOTE_DEBUG_PAIR_URL"],
                       let url = URL(string: string) {
                        client.handle(url: url)
                    }
                    #endif
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        idle.foregrounded()
                        client.start()
                    case .inactive:
                        // System alerts (including the Local Network permission prompt, which the
                        // first browse triggers) leave the app inactive, not backgrounded: keep
                        // discovery running so the prompt can appear and Macs show up behind it.
                        client.start()
                    case .background:
                        idle.backgrounded()
                        client.stop()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
