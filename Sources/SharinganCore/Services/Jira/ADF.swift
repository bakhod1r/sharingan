import Foundation

/// Atlassian Document Format helpers.
///
/// Jira Cloud's REST v3 represents descriptions and comments as ADF — a nested
/// JSON node tree. Modelling it fully is a large undertaking, so v1 treats it as
/// a two-way *plain-text* bridge: rich Jira content is rendered read-only as
/// text, and anything written from Sharingan is emitted as minimal ADF. Editing
/// a description from here therefore replaces its formatting with plain text;
/// the UI shows a caption saying so. The raw ADF is kept in the local cache so
/// nothing is lost until the user actually edits.
public enum ADF {

    /// Build a minimal ADF document from plain text — one paragraph per line.
    /// Empty input yields a valid empty document (Jira requires the wrapper).
    public static func document(fromPlainText text: String) -> Data {
        let lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let paragraphs: [[String: Any]] = lines.map { line in
            if line.isEmpty {
                return ["type": "paragraph"]
            }
            return [
                "type": "paragraph",
                "content": [["type": "text", "text": line]],
            ]
        }
        let doc: [String: Any] = [
            "type": "doc",
            "version": 1,
            "content": paragraphs,
        ]
        return (try? JSONSerialization.data(withJSONObject: doc)) ?? Data()
    }

    /// Extract readable plain text from an ADF document.
    ///
    /// Walks the `content` tree: `text` nodes contribute their string,
    /// `hardBreak` becomes a newline, list items are prefixed with "- ",
    /// mentions render as "@name", and block nodes (paragraph, heading,
    /// listItem, blockquote) are separated by newlines. Unknown node types
    /// degrade gracefully to whatever text their children carry.
    public static func plainText(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        var out = ""
        renderNode(root, into: &out, listDepth: 0)
        // Collapse the runs of blank lines that block separators can produce.
        let trimmed = out.replacingOccurrences(
            of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let blockTypes: Set<String> = [
        "paragraph", "heading", "blockquote", "codeBlock", "panel", "rule",
    ]

    private static func renderNode(_ node: [String: Any], into out: inout String, listDepth: Int) {
        let type = node["type"] as? String ?? ""

        switch type {
        case "text":
            out += node["text"] as? String ?? ""
            return
        case "hardBreak":
            out += "\n"
            return
        case "mention":
            let attrs = node["attrs"] as? [String: Any]
            let name = attrs?["text"] as? String ?? "@unknown"
            out += name.hasPrefix("@") ? name : "@\(name)"
            return
        case "emoji":
            let attrs = node["attrs"] as? [String: Any]
            out += attrs?["text"] as? String ?? (attrs?["shortName"] as? String ?? "")
            return
        case "rule":
            out += "\n---\n"
            return
        default:
            break
        }

        let children = node["content"] as? [[String: Any]] ?? []

        switch type {
        case "bulletList", "orderedList":
            for (index, item) in children.enumerated() {
                renderListItem(item, index: index, ordered: type == "orderedList",
                               into: &out, listDepth: listDepth)
            }
        default:
            for child in children {
                renderNode(child, into: &out, listDepth: listDepth)
            }
            if blockTypes.contains(type) {
                out += "\n"
            }
        }
    }

    private static func renderListItem(_ item: [String: Any], index: Int, ordered: Bool,
                                       into out: inout String, listDepth: Int) {
        let indent = String(repeating: "  ", count: listDepth)
        let marker = ordered ? "\(index + 1). " : "- "
        out += indent + marker
        let children = item["content"] as? [[String: Any]] ?? []
        for child in children {
            let childType = child["type"] as? String ?? ""
            if childType == "bulletList" || childType == "orderedList" {
                out += "\n"
                renderNode(child, into: &out, listDepth: listDepth + 1)
            } else {
                renderNode(child, into: &out, listDepth: listDepth)
            }
        }
        if !out.hasSuffix("\n") { out += "\n" }
    }
}
