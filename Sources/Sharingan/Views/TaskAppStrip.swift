import SwiftUI
import SharinganCore

/// The apps a task was focused in, shown under an expanded Report row: an
/// **APPS** header then one icon · name · duration line per app, most-used
/// first. Indented to sit under the task title. Uses AnalyticsAppsView's cached
/// bundle → name/icon lookup so every surface resolves apps the same way.
///
/// Its own view so the Report row and the headless dev-preview render share the
/// exact same layout — the preview photographs what ships, not a copy of it.
struct TaskAppStrip: View {
    let apps: [AnalyticsEngine.AppTotal]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("APPS")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.35))
            ForEach(apps) { app in
                HStack(spacing: 8) {
                    Image(nsImage: AnalyticsAppsView.icon(for: app.bundleID))
                        .resizable().frame(width: 15, height: 15)
                    Text(AnalyticsAppsView.name(for: app.bundleID))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(AnalyticsAppsView.durationLabel(app.seconds))
                        .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.leading, 38).padding(.trailing, 12).padding(.top, 2).padding(.bottom, 6)
    }
}
