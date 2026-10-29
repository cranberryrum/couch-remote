import SwiftUI
import UIKit

@main
struct RemoteiPhoneApp: App {
    @State private var client = RemoteClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(client: client)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        UIApplication.shared.isIdleTimerDisabled = true
                        client.start()
                    case .background:
                        UIApplication.shared.isIdleTimerDisabled = false
                        client.stop()
                    default:
                        break
                    }
                }
        }
    }
}
