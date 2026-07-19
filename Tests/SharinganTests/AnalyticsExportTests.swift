import Testing
import Foundation
@testable import SharinganCore

@Suite("Analytics export")
struct AnalyticsExportTests {
    private func sample() -> [SessionRecord] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            SessionRecord(start: start, end: start.addingTimeInterval(1500),
                          phase: .focus, completed: true, taskTitle: "Write, edit",
                          plannedSeconds: 1500),
            SessionRecord(start: start.addingTimeInterval(1800),
                          end: start.addingTimeInterval(2100),
                          phase: .shortBreak, completed: false, plannedSeconds: 300),
        ]
    }

    @Test func csvHasHeaderAndEscapesCommas() {
        let csv = String(data: AnalyticsExport.csv(from: sample()), encoding: .utf8)!
        #expect(csv.hasPrefix("Date,Start,End,Phase,Completed,Minutes,Task"))
        #expect(csv.contains("\"Write, edit\""))   // comma-containing field quoted
        #expect(csv.contains("focus,yes,25"))
    }

    @Test func crc32MatchesKnownVector() {
        // "123456789" → 0xCBF43926 is the standard CRC-32 check value.
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func xlsxIsAValidZipContainer() {
        let data = AnalyticsExport.xlsx(from: sample())
        // Local file header signature "PK\u{03}\u{04}".
        #expect(Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
        // End-of-central-directory signature present near the end.
        #expect(data.range(of: Data([0x50, 0x4B, 0x05, 0x06])) != nil)
        // Contains the worksheet part name.
        #expect(data.range(of: Data("xl/worksheets/sheet1.xml".utf8)) != nil)
    }

    @Test func xlsxUnzipsToValidParts() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharingan-export-check.xlsx")
        try AnalyticsExport.xlsx(from: sample()).write(to: url)
        // A real ZIP reader must accept it and find the required parts.
        let listing = try shell("/usr/bin/unzip", ["-l", url.path])
        #expect(listing.contains("[Content_Types].xml"))
        #expect(listing.contains("xl/workbook.xml"))
        #expect(listing.contains("xl/worksheets/sheet1.xml"))
        try? FileManager.default.removeItem(at: url)
    }

    private func shell(_ launch: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                      encoding: .utf8) ?? ""
    }

    @Test func columnNamesRollOver() {
        #expect(XLSXWriter.columnName(0) == "A")
        #expect(XLSXWriter.columnName(25) == "Z")
        #expect(XLSXWriter.columnName(26) == "AA")
    }
}
