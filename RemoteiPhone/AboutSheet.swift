import RemoteKit
import SwiftUI

/// About the creator: the app is free, so this is where the thanks go.
struct AboutSheet: View {
    @Environment(\.theme) private var theme

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "CouchRemote \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Made by \(Creator.name)")
                        .font(.title2.bold())
                        .foregroundStyle(theme.foreground)
                    Text("I built CouchRemote so I could watch from bed without getting up. It's free and open source. If it's useful to you, say hi.")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                }
                .padding(.top, 28)

                Card {
                    linkRow("globe", "Website", Creator.websiteLabel, Creator.website)
                    RowDivider()
                    linkRow("at", "X (Twitter)", Creator.twitterLabel, Creator.twitter)
                    RowDivider()
                    linkRow("chevron.left.forwardslash.chevron.right", "Source code", "GitHub", Creator.sourceCode)
                }

                Text(version)
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.sheetBackground)
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
                .presentationDetents([.fraction(0.5), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.surface)
                .presentationBackground(theme.sheetBackground)
                .preferredColorScheme(.dark)
        }
    }
}
