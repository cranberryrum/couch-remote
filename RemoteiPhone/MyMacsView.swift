import RemoteKit
import SwiftUI

/// Home screen whenever you're not connected. Nothing here connects by itself.
struct MyMacsView: View {
    let client: RemoteClient
    @Binding var night: Bool

    @Environment(\.theme) private var theme
    @State private var showScanner = false
    #if DEBUG
    // Test hook: COUCHREMOTE_DEBUG_OPEN_GET_MAC=1 opens the sheet at launch (simulator screenshots).
    @State private var showGetMac = ProcessInfo.processInfo.environment["COUCHREMOTE_DEBUG_OPEN_GET_MAC"] != nil
    #else
    @State private var showGetMac = false
    #endif
    @State private var renaming: PairedMac?
    @State private var renameText = ""
    @State private var forgetting: PairedMac?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("My Macs")
                    .font(.largeTitle.bold())
                    .foregroundStyle(theme.foreground)
                Spacer()
                Button {
                    night.toggle()
                } label: {
                    Image(systemName: night ? "moon.fill" : "moon")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.foreground)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Night mode")
            }

            if let notice = client.notice {
                Banner(text: notice, symbol: "info.circle.fill") { client.notice = nil }
            }
            if client.localNetworkDenied {
                Banner(text: "Local Network access is off. Enable it in Settings › CouchRemote to find your Macs.", symbol: "wifi.exclamationmark", action: nil)
            }

            if client.pairedMacs.isEmpty {
                emptyState
            } else {
                macList
            }

            Button {
                showScanner = true
            } label: {
                Label("Pair another Mac", systemImage: "qrcode.viewfinder")
                    .font(.headline)
                    .foregroundStyle(theme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(TapStyle(radius: Radius.card))

            // Always reachable: a friend who just installed the phone app starts here.
            Button {
                showGetMac = true
            } label: {
                Label("Get the Mac app", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .getMacAppSheet(isPresented: $showGetMac, theme: theme)
        .sheet(isPresented: $showScanner) {
            PairingScannerView { code in
                guard let url = URL(string: code), PairingInvite(url: url) != nil else { return false }
                client.handle(url: url)
                showScanner = false
                return true
            }
        }
        .alert("Rename Mac", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let mac = renaming { client.rename(mac.macID, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Leave empty to use the Mac's own name.")
        }
        .confirmationDialog(
            "Forget \(forgetting?.displayName ?? "this Mac")?",
            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
            titleVisibility: .visible,
            presenting: forgetting
        ) { mac in
            Button("Forget", role: .destructive) { client.forget(mac.macID) }
        } message: { _ in
            Text("You'll need to pair it again from the Mac's “Pair New iPhone…” menu.")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 40))
                .foregroundStyle(theme.secondary)
            Text("Set up your Mac")
                .font(.title2.bold())
                .foregroundStyle(theme.foreground)
            VStack(alignment: .leading, spacing: 14) {
                emptyStep(1, "Get the free CouchRemote app on your Mac.")
                emptyStep(2, "Open it and choose “Pair New iPhone…” from its menu-bar icon.")
                emptyStep(3, "Tap “Pair another Mac” below and scan the code.")
            }
            Button {
                showGetMac = true
            } label: {
                Label("Get the Mac app", systemImage: "arrow.down.circle")
                    .font(.headline)
                    .foregroundStyle(theme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(TapStyle(radius: Radius.card, prominent: true))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func emptyStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.foreground)
                .frame(width: 24, height: 24)
                .background(theme.controlFill, in: Circle())
            Text(text)
                .font(.body)
                .foregroundStyle(theme.foreground)
        }
    }

    private var macList: some View {
        List {
            ForEach(client.pairedMacs) { mac in
                row(mac)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(theme.controlFill)
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Forget", role: .destructive) { forgetting = mac }
                    }
                    .contextMenu {
                        Button("Rename") {
                            renameText = mac.customName ?? ""
                            renaming = mac
                        }
                        Button("Forget", role: .destructive) { forgetting = mac }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ mac: PairedMac) -> some View {
        let online = client.isOnline(mac.macID)
        let connecting = client.phase == .connecting(mac.macID)
        let busy: Bool = { if case .connecting = client.phase { return true } else { return false } }()

        return HStack(spacing: 12) {
            Circle()
                .fill(online ? theme.good : theme.bad.opacity(0.7))
                .frame(width: 9, height: 9)
                .padding(.leading, 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.displayName)
                    .font(.headline)
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                Text(connecting ? "Connecting…" : (online ? "Online" : "Offline"))
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }
            Spacer()
            if connecting {
                ProgressView().tint(theme.foreground).padding(.trailing, 18)
            } else {
                Button("Connect") { client.connect(mac.macID) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: Radius.chip))
                    .tint(theme.night ? theme.good.opacity(0.5) : .accentColor)
                    .disabled(!online || busy)
                    .padding(.trailing, 10)
            }
        }
        .frame(minHeight: 62)
    }
}

struct Banner: View {
    let text: String
    let symbol: String
    let action: (() -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(theme.accent)
            Text(text)
                .font(.footnote)
                .foregroundStyle(theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action: action) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(theme.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(theme.controlFill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}
