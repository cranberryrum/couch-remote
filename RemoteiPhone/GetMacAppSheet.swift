import SwiftUI

enum MacApp {
    /// Downloads the newest notarized DMG the moment it's opened on a Mac. The release carries an
    /// unversioned `CouchRemote.dmg` next to the versioned one so this link never changes.
    static let downloadURL = URL(string: "https://github.com/cranberryrum/couch-remote/releases/latest/download/CouchRemote.dmg")!
}

/// How a first-time user gets the Mac companion app: share the link to the Mac (AirDrop, Messages, …),
/// copy it, or scan the code from another device.
struct GetMacAppSheet: View {
    @Environment(\.theme) private var theme
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Get the Mac app")
                        .font(.title2.bold())
                        .foregroundStyle(theme.foreground)
                    Text("CouchRemote needs a small free app on your Mac. Send yourself the link and open it on the Mac.")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                }
                .padding(.top, 28)

                VStack(spacing: 10) {
                    ShareLink(item: MacApp.downloadURL, subject: Text("CouchRemote for Mac")) {
                        Label("Send link to my Mac", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(TapStyle(radius: Radius.card, prominent: true))

                    Button {
                        UIPasteboard.general.string = MacApp.downloadURL.absoluteString
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(TapStyle(radius: Radius.control))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("ON YOUR MAC")
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(theme.secondary)
                    step(1, "Open the link: the download starts. Open the DMG and drag CouchRemote to Applications.")
                    step(2, "Open it and allow Accessibility when asked. A small icon appears in the menu bar.")
                    step(3, "Choose “Pair New iPhone…” from that icon, then scan the code here.")
                }
                .padding(.leading, 4)

                Text("Needs macOS 14 or later, on the same Wi-Fi as this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.sheetBackground)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.foreground)
                .frame(width: 24, height: 24)
                .background(theme.controlFill, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(theme.foreground)
        }
    }
}

extension View {
    /// The Get-the-Mac-app sheet, styled like the Controls sheet.
    func getMacAppSheet(isPresented: Binding<Bool>, theme: Theme) -> some View {
        sheet(isPresented: isPresented) {
            GetMacAppSheet()
                .environment(\.theme, theme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.surface)
                .presentationBackground(theme.sheetBackground)
                .preferredColorScheme(.dark)
        }
    }
}
