import Foundation

/// A dependency-free .xlsx writer: a store-only ZIP of minimal SpreadsheetML.
/// Enough to open cleanly in Excel / Numbers / Sheets. Values that look numeric
/// are written as numbers; everything else as inline strings (XML-escaped).
public enum XLSXWriter {
    public struct Sheet {
        public var name: String
        public var rows: [[String]]
        public init(name: String, rows: [[String]]) {
            self.name = name; self.rows = rows
        }
    }

    public static func build(sheets: [Sheet]) -> Data {
        var files: [(String, Data)] = []
        files.append(("[Content_Types].xml", contentTypes(count: sheets.count).data(using: .utf8)!))
        files.append(("_rels/.rels", rootRels.data(using: .utf8)!))
        files.append(("xl/workbook.xml", workbook(sheets: sheets).data(using: .utf8)!))
        files.append(("xl/_rels/workbook.xml.rels", workbookRels(count: sheets.count).data(using: .utf8)!))
        for (i, sheet) in sheets.enumerated() {
            files.append(("xl/worksheets/sheet\(i + 1).xml",
                          worksheet(sheet).data(using: .utf8)!))
        }
        return Zip.archive(files: files)
    }

    // MARK: - XML parts

    private static func contentTypes(count: Int) -> String {
        var overrides = ""
        for i in 1...max(1, count) {
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\(overrides)</Types>
        """
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static func workbook(sheets: [Sheet]) -> String {
        var entries = ""
        for (i, sheet) in sheets.enumerated() {
            entries += "<sheet name=\"\(escape(sheet.name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(entries)</sheets></workbook>
        """
    }

    private static func workbookRels(count: Int) -> String {
        var rels = ""
        for i in 1...max(1, count) {
            rels += "<Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
        """
    }

    private static func worksheet(_ sheet: Sheet) -> String {
        var rowsXML = ""
        for (r, row) in sheet.rows.enumerated() {
            var cells = ""
            for (c, value) in row.enumerated() {
                let ref = "\(columnName(c))\(r + 1)"
                if let num = numericValue(value) {
                    cells += "<c r=\"\(ref)\"><v>\(num)</v></c>"
                } else {
                    cells += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
                }
            }
            rowsXML += "<row r=\"\(r + 1)\">\(cells)</row>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rowsXML)</sheetData></worksheet>
        """
    }

    // MARK: - Helpers

    /// A1-style column name for a 0-based index.
    public static func columnName(_ index: Int) -> String {
        var n = index, name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + n % 26))) + name
            n = n / 26 - 1
        } while n >= 0
        return name
    }

    private static func numericValue(_ s: String) -> String? {
        guard !s.isEmpty, Double(s) != nil else { return nil }
        return s
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
