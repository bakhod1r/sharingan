import SwiftUI
import AppKit
import SharinganCore

/// Analytics → Export: save the (filtered) session history as CSV, XLSX, or a
/// one-page PDF summary. The heavy lifting is in `AnalyticsExport`; this just
/// runs a save panel and writes the bytes.
struct AnalyticsExportView: View {
    let sessions: [SessionRecord]
    var accent: Color
    var range: AnalyticsFilter.Range
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") in the current filter (\(range.rawValue)).")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))

            HStack(spacing: 12) {
                button("CSV", "tablecells") { save(ext: "csv", data: AnalyticsExport.csv(from: sessions)) }
                button("Excel (.xlsx)", "tablecells.fill") { save(ext: "xlsx", data: AnalyticsExport.xlsx(from: sessions)) }
                button("PDF", "doc.richtext") { savePDF() }
            }

            if let status {
                Text(status)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    private func button(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(accent.opacity(0.85)))
        }
        .buttonStyle(.pressableSubtle)
        .disabled(sessions.isEmpty)
        .opacity(sessions.isEmpty ? 0.4 : 1)
    }

    private func save(ext: String, data: Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sharingan-analytics.\(ext)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            status = "Saved to \(url.lastPathComponent)."
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func savePDF() {
        let summary = ExportPDFPage(sessions: sessions, accent: accent, range: range)
        let renderer = ImageRenderer(content: summary)
        renderer.proposedSize = ProposedViewSize(width: 612, height: 792)  // US Letter pt
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sharingan-analytics.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        renderer.render { size, render in
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            render(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        status = "Saved to \(url.lastPathComponent)."
    }
}

/// The rendered one-page PDF summary (light background, print-friendly).
private struct ExportPDFPage: View {
    let sessions: [SessionRecord]
    var accent: Color
    var range: AnalyticsFilter.Range

    private var focusCount: Int { sessions.filter { $0.phase == .focus && $0.completed }.count }
    private var focusHours: Double {
        sessions.filter { $0.phase == .focus }.reduce(0) { $0 + $1.seconds } / 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sharingan — Focus Report")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Range: \(range.rawValue) · \(sessions.count) sessions")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 40) {
                stat("\(focusCount)", "Completed pomodoros")
                stat(String(format: "%.1f h", focusHours), "Focus time")
            }
            Divider()
            ForEach(AnalyticsExport.rows(from: sessions).prefix(30), id: \.self) { row in
                Text(row.joined(separator: "   ·   "))
                    .font(.system(size: 10, design: .monospaced))
            }
            if sessions.count > 30 {
                Text("… and \(sessions.count - 30) more (full data in the CSV/XLSX export).")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(36)
        .frame(width: 612, height: 792, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            Text(label).font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
