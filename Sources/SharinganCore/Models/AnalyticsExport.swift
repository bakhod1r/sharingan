import Foundation

/// Builds export payloads (CSV / XLSX) from the session log — pure, so it's
/// unit-tested and the view just writes the bytes to disk.
public enum AnalyticsExport {
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()

    public static let headers = ["Date", "Start", "End", "Phase", "Completed",
                                 "Minutes", "Task"]

    /// One row per session (task-level attribution snapshot).
    public static func rows(from sessions: [SessionRecord]) -> [[String]] {
        sessions.sorted { $0.start < $1.start }.map { s in
            [dateFmt.string(from: s.start).prefix(10).description,
             dateFmt.string(from: s.start).suffix(5).description,
             dateFmt.string(from: s.end).suffix(5).description,
             s.phase.rawValue,
             s.completed ? "yes" : "no",
             String(Int(s.seconds / 60)),
             s.taskTitle ?? ""]
        }
    }

    public static func csv(from sessions: [SessionRecord]) -> Data {
        var lines = [headers.map(escapeCSV).joined(separator: ",")]
        for row in rows(from: sessions) {
            lines.append(row.map(escapeCSV).joined(separator: ","))
        }
        return (lines.joined(separator: "\r\n") + "\r\n").data(using: .utf8) ?? Data()
    }

    public static func xlsx(from sessions: [SessionRecord]) -> Data {
        let sheet = XLSXWriter.Sheet(name: "Sessions",
                                     rows: [headers] + rows(from: sessions))
        return XLSXWriter.build(sheets: [sheet])
    }

    private static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
