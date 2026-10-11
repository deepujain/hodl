import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            AppIconArtwork()
                .scaleEffect(180 / 1024)
                .frame(width: 180, height: 180)
            VStack(spacing: 4) {
                Text(verbatim: "HODL")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                Text("Hold the Door Lid")
                    .foregroundStyle(.secondary)
                Text("Version \(Bundle.main.shortVersion)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Text("Keeps your Mac awake overnight so Cursor, Claude Code, Codex, Aider, and Pi keep working, with the lid open or closed. It lets go when your agents finish, the battery runs low, or the Mac gets hot.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .frame(maxWidth: 360)
            Label("Keep the Mac on a desk or stand, not in a closed bag.", systemImage: "wind")
                .font(.caption).foregroundStyle(.secondary)
            Link(AppLinks.repositoryLabel, destination: AppLinks.repository)
                .font(.caption)
        }
        .padding(32)
        .padding(.top, 8)
        .frame(width: 440)
    }
}
