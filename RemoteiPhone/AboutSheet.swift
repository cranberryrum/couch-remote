import RemoteKit
import SwiftUI

/// About the creator: the app is free, so this is where the thanks go.
struct AboutSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "CouchRemote \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                avatar
                    .padding(.top, 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Made by \(Creator.name)")
                        .font(.title2.bold())
                        .foregroundStyle(theme.foreground)
                    Text("I built CouchRemote so I could watch from bed without getting up. It's free and open source. If it's useful to you, say hi.")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                }
                .reveal(shown, order: 1, reduceMotion: reduceMotion)

                Card {
                    linkRow("globe", "Website", Creator.websiteLabel, Creator.website)
                    RowDivider()
                    linkRow("at", "X (Twitter)", Creator.twitterLabel, Creator.twitter)
                    RowDivider()
                    linkRow("chevron.left.forwardslash.chevron.right", "Source code", "GitHub", Creator.sourceCode)
                }
                .reveal(shown, order: 2, reduceMotion: reduceMotion)

                Text(version)
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 4)
                    .reveal(shown, order: 3, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.sheetBackground)
        .task {
            // Let the sheet's own slide-in start first, then bring the content in behind it.
            try? await Task.sleep(for: .milliseconds(50))
            shown = true
        }
    }

    /// Continuous ("smoothed") corners, a hairline edge so the yellow doesn't bleed into the dark sheet.
    private var avatar: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return Image("Creator")
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 96)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .accessibilityLabel("Portrait of \(Creator.name)")
            // It arrives out of a soft blur and settles with a small, slightly springy scale-up.
            // Scale is the innermost modifier, so it takes the spring; opacity and blur take the ease-out.
            .scaleEffect(shown || reduceMotion ? 1 : 0.88, anchor: .topLeading)
            .animation(.spring(duration: 0.5, bounce: 0.18).delay(0.06), value: shown)
            .blur(radius: shown || reduceMotion ? 0 : 8)
            .opacity(shown ? 1 : 0)
            .animation(Motion.easeOut(0.35).delay(0.06), value: shown)
    }

    private func linkRow(_ symbol: String, _ title: String, _ detail: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 24)
                Text(title)
                Spacer(minLength: 8)
                Text(detail)
                    .foregroundStyle(theme.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.secondary)
            }
            .font(.body)
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
    }
}

extension View {
    /// The About sheet, styled like the other sheets.
    func aboutSheet(isPresented: Binding<Bool>, theme: Theme) -> some View {
        sheet(isPresented: isPresented) {
            AboutSheet()
                .environment(\.theme, theme)
                .presentationDetents([.fraction(0.68), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.surface)
                .presentationBackground(theme.sheetBackground)
                .preferredColorScheme(.dark)
        }
    }
}

private extension View {
    /// Fades up into place, `order` steps after the avatar (60 ms apart, so the whole thing lands in
    /// well under half a second). With Reduce Motion it only fades.
    func reveal(_ shown: Bool, order: Int, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(Motion.easeOut(0.38).delay(0.06 + 0.06 * Double(order)), value: shown)
    }
}
