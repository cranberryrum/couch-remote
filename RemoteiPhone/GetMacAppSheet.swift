import CoreImage.CIFilterBuiltins
import SwiftUI

enum MacApp {
    /// Always lands on the newest release, which carries the notarized DMG.
    static let downloadURL = URL(string: "https://github.com/cranberryrum/couch-remote/releases/latest")!
}

/// How a first-time user gets the Mac companion app: share the link to the Mac (AirDrop, Messages, …),
/// copy it, or scan the code from another device.
struct GetMacAppSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Get the Mac app")
                        .font(.title2.bold())
                        .foregroundStyle(theme.foreground)
                    Text("CouchRemote needs a small free app on your Mac. Send yourself the link and open it there.")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                }
                .padding(.top, 6)

                HStack(alignment: .center, spacing: 16) {
                    QRView(string: MacApp.downloadURL.absoluteString)
                        .frame(width: 112, height: 112)
                        .accessibilityHidden(true)
                    Text("Or scan this code with another device, then open the link on your Mac.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondary)
                }

                VStack(spacing: 10) {
                    ShareLink(item: MacApp.downloadURL, subject: Text("CouchRemote for Mac")) {
                        Label("Send link to my Mac", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(TapStyle(radius: Radius.card, prominent: true))

                    HStack(spacing: 10) {
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
                        Button {
                            openURL(MacApp.downloadURL)
                        } label: {
                            Label("Open here", systemImage: "safari")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(TapStyle(radius: Radius.control))
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("ON YOUR MAC")
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(theme.secondary)
                    step(1, "Download CouchRemote-…dmg from the page and drag the app to Applications.")
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

/// Dark-on-light QR code (scanners need the light quiet zone, so it ignores night mode).
private struct QRView: View {
    let string: String

    var body: some View {
        if let image = Self.render(string) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        }
    }

    private static func render(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
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
