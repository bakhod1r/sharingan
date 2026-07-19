import SwiftUI
import AppKit
import SharinganCore

/// Analytics → Apps: which apps were frontmost during focus, ranked by time,
/// with an icon, a share bar, and the duration. Fed by `appUsage` on the
/// session records (populated by `ActiveAppTracker`).
struct AnalyticsAppsView: View {
    let totals: [AnalyticsEngine.AppTotal]
    var accent: Color
    var range: AnalyticsFilter.Range
    var trackingMode: AppTrackingMode

    private var maxSeconds: TimeInterval { totals.first?.seconds ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(range.rawValue) · app focus time")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            if trackingMode == .off {
                hint("App tracking is off. Turn it on in Settings → Analytics to see which apps you focus in.")
            } else if totals.isEmpty {
                hint("No app activity recorded yet — it fills in as you run focus sessions with tracking on.")
            } else {
                ForEach(totals) { total in row(total) }
            }
        }
        .padding(16)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
    }

    private func row(_ total: AnalyticsEngine.AppTotal) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: Self.icon(for: total.bundleID))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Self.name(for: total.bundleID))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(Self.durationLabel(total.seconds))
                        .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                GeometryReader { geo in
                    Capsule().fill(Color.white.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule().fill(accent.opacity(0.85))
                                .frame(width: geo.size.width * CGFloat(total.seconds / maxSeconds))
                        }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bundle → name / icon (cached)

    private static var nameCache: [String: String] = [:]
    private static var iconCache: [String: NSImage] = [:]

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        if let cached = nameCache[bundleID] { return cached }
        let resolved = url(for: bundleID).map {
            FileManager.default.displayName(atPath: $0.path)
                .replacingOccurrences(of: ".app", with: "")
        } ?? bundleID
        nameCache[bundleID] = resolved
        return resolved
    }

    static func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let img: NSImage
        if let u = url(for: bundleID) {
            img = NSWorkspace.shared.icon(forFile: u.path)
        } else {
            img = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
                ?? NSImage()
        }
        iconCache[bundleID] = img
        return img
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }
}
