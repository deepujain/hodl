import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            AppIconArtwork()
                .scaleEffect(200 / 1024)
                .frame(width: 200, height: 200)
                .padding(.top, 26)

            VStack(spacing: 6) {
                Text(verbatim: "HODL")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Keeps your Mac awake so your AI agents keep working overnight.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 284)
                    .padding(.top, 4)
            }

            HStack(spacing: 10) {
                Text("Made by")
                    .foregroundStyle(.secondary)
                Text(verbatim: "1xAI")
                    .font(.system(.body, design: .rounded).weight(.heavy))
            }
            .padding(.top, 18)

            Link(destination: AppLinks.website) {
                Label("Visit the website", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 10)

            Text(verbatim: Bundle.main.copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
                .padding(.bottom, 22)
        }
        .frame(width: 340)
        .background(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.55, green: 0.52, blue: 0.95).opacity(0.45),
                                    Color(red: 0.45, green: 0.85, blue: 0.80).opacity(0.22), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .ignoresSafeArea()
        }
    }
}
