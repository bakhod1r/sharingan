import Foundation

/// Parses a pasted or dropped document — the Markdown template, a plain
/// checklist, or JSON — into ready-to-insert `TaskItem`s. Pure; pass `now`
/// for deterministic tests. The caller hands each result to
/// `TaskStore.insert`, which assigns sort order and persists.
///
/// Format is auto-detected: text starting with `{` or `[` is JSON, anything
/// else is Markdown. Markdown comes in two shapes:
/// - **Heading blocks** — every `#`/`##` heading starts a task. The heading
///   text runs through `TaskInputParser`, so quick-add tokens
///   (`p1 #tag @proj ~4 tomorrow 15:00`) work in all its languages. Inside a
///   block, `key: value` lines refine the task, `- [ ]` lines are subtasks,
///   and any other text becomes notes.
/// - **Flat checklist** (no headings) — each top-level `- …` line is one task
///   (also via `TaskInputParser`); indented list lines under it are its
///   subtasks. A document with neither headings nor list lines imports each
///   non-empty line as a task.
public enum TaskImportParser {

    public static func parse(_ raw: String, now: Date = Date()) -> [TaskItem] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return parseJSON(trimmed, now: now)
        }
        return parseMarkdown(trimmed, now: now)
    }

    // MARK: - Markdown

    private static func parseMarkdown(_ text: String, now: Date) -> [TaskItem] {
        let lines = text.components(separatedBy: .newlines)
        if lines.contains(where: { headingText($0) != nil }) {
            return parseHeadingBlocks(lines, now: now)
        }
        return parseChecklist(lines, now: now)
    }

    private static func parseHeadingBlocks(_ lines: [String], now: Date) -> [TaskItem] {
        var tasks: [TaskItem] = []
        var current: TaskItem?
        var notes: [String] = []

        func finalize() {
            guard var t = current else { return }
            t.notes = mergedNotes(t.notes, notes)
            tasks.append(t)
            current = nil
            notes = []
        }

        for line in lines {
            if let heading = headingText(line) {
                finalize()
                current = task(fromQuickAdd: heading, now: now)
                continue
            }
            guard current != nil else { continue }   // preamble before the first heading
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let sub = subtaskLine(line) {
                current?.subtasks.append(sub)
            } else if let (key, value) = keyValueLine(trimmed) {
                apply(key: key, value: value, to: &current!, notes: &notes, now: now)
            } else {
                notes.append(trimmed)
            }
        }
        finalize()
        return tasks
    }

    /// Flat list: top-level bullets are tasks, indented bullets their subtasks;
    /// a document with no bullets at all imports each non-empty line as a task.
    private static func parseChecklist(_ lines: [String], now: Date) -> [TaskItem] {
        var tasks: [TaskItem] = []
        let hasBullets = lines.contains { listItem($0) != nil }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if hasBullets {
                guard let (indent, checked, rest) = listItem(line) else { continue }
                if indent == 0 {
                    var t = task(fromQuickAdd: rest, now: now)
                    if checked { t.isDone = true; t.completedAt = now }
                    tasks.append(t)
                } else if !tasks.isEmpty, let sub = subtaskLine(line) {
                    tasks[tasks.count - 1].subtasks.append(sub)
                }
            } else {
                tasks.append(task(fromQuickAdd: trimmed, now: now))
            }
        }
        return tasks
    }

    /// `# Title` … `###### Title` → the title text; `#tag` (no space) is not
    /// a heading.
    private static func headingText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard hashes.count <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// `- [x] text` / `* text` → (leading spaces, checked, text).
    private static func listItem(_ line: String) -> (indent: Int, checked: Bool, rest: String)? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
            .reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        var s = line.trimmingCharacters(in: .whitespaces)
        guard let bullet = s.first, "-*+".contains(bullet) else { return nil }
        s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        var checked = false
        for (box, isChecked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where s.hasPrefix(box) {
            checked = isChecked
            s = String(s.dropFirst(box.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard !s.isEmpty else { return nil }
        return (indent, checked, s)
    }

    /// A list line as a subtask: a trailing `~N` is the step estimate, a
    /// trailing `(small|normal|big)` its pomodoro size.
    private static func subtaskLine(_ line: String) -> Subtask? {
        guard let (_, checked, rest) = listItem(line) else { return nil }
        var estimate: Int?
        var kind: PomodoroKind?
        var kept: [String] = []
        for word in rest.split(separator: " ").map(String.init) {
            if word.hasPrefix("~"), let n = Int(word.dropFirst()), n > 0 {
                estimate = n
            } else if word.hasPrefix("("), word.hasSuffix(")"),
                      let k = pomodoroKind(String(word.dropFirst().dropLast())) {
                kind = k
            } else {
                kept.append(word)
            }
        }
        let title = kept.joined(separator: " ")
        guard !title.isEmpty else { return nil }
        return Subtask(title: title, isDone: checked,
                       estimatedPomodoros: estimate, pomodoroKind: kind)
    }

    /// Splits `key: value` when the key is one we know (English or Uzbek);
    /// anything else — "Meeting: discuss X" — stays a notes line.
    private static func keyValueLine(_ line: String) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let rawKey = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard let key = keyAliases[rawKey] else { return nil }
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        return (key, value)
    }

    /// Alias → canonical field. Keys are matched case-insensitively.
    private static let keyAliases: [String: String] = [
        "category": "category", "kategoriya": "category",
        "project": "project", "proyekt": "project", "loyiha": "project",
        "tags": "tags", "teglar": "tags", "taglar": "tags",
        "priority": "priority", "muhimlik": "priority",
        "due": "due", "duedate": "due", "deadline": "due", "muddat": "due",
        "planned": "planned", "plan": "planned", "reja": "planned",
        "estimate": "estimate", "estimatedpomodoros": "estimate", "baho": "estimate",
        "repeat": "repeat", "recurrence": "repeat", "takror": "repeat",
        "pomodoro": "pomodoro", "pomodorokind": "pomodoro",
        "notes": "notes", "eslatma": "notes", "izoh": "notes",
        "done": "done", "bajarildi": "done",
    ]

    private static func apply(key: String, value: String, to task: inout TaskItem,
                              notes: inout [String], now: Date) {
        switch key {
        case "category": task.category = value
        case "project":  task.project = value
        case "tags":     task.tags = tagList(value)
        case "priority": if let p = priority(value) { task.priority = p }
        case "due":      task.dueDate = date(value, now: now)
        case "planned":
            if let d = date(value, now: now) {
                task.plannedDate = Calendar.current.startOfDay(for: d)
            }
        case "estimate":
            if let n = Int(value.replacingOccurrences(of: "~", with: "")), n > 0 {
                task.estimatedPomodoros = n
            }
        case "repeat":   task.recurrence = recurrence(value, now: now)
        case "pomodoro": task.pomodoroKind = pomodoroKind(value)
        case "notes":    notes.append(value)
        case "done":
            if truthy(value) { task.isDone = true; task.completedAt = now }
        default: break
        }
    }

    // MARK: - Value parsing (shared by markdown and JSON)

    /// The heading/checklist line through the quick-add parser; a line the
    /// parser consumes entirely (`# p1 #ish`) keeps its raw text as title.
    private static func task(fromQuickAdd line: String, now: Date) -> TaskItem {
        let p = TaskInputParser.parse(line, now: now)
        var t = TaskItem(title: p.title.isEmpty ? line : p.title, createdAt: now)
        t.tags = p.tags
        t.project = p.project
        t.priority = p.priority
        t.dueDate = p.dueDate
        t.estimatedPomodoros = p.estimatedPomodoros
        t.recurrence = p.recurrence
        return t
    }

    private static func tagList(_ value: String) -> [String] {
        value.split(separator: ",").map {
            var s = $0.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { s = String(s.dropFirst()) }
            return s
        }.filter { !$0.isEmpty }
    }

    /// "P1"…"P4", high/medium/low/none (plus Uzbek), or an int P-number
    /// (1 = urgent).
    private static func priority(_ value: String) -> TaskPriority? {
        switch value.lowercased() {
        case "p1", "high", "urgent", "yuqori": return .high
        case "p2", "medium", "o'rta", "orta":  return .medium
        case "p3", "low", "past":              return .low
        case "p4", "none", "yo'q", "yoq":      return TaskPriority.none
        default:
            if let n = Int(value), (1...4).contains(n) {
                return TaskPriority(rawValue: 4 - n)
            }
            return nil
        }
    }

    /// `yyyy-MM-dd [HH:mm]`, ISO-8601, or any natural-language phrase the
    /// quick-add parser understands ("tomorrow 15:00", "ertaga", "12.08").
    private static func date(_ value: String, now: Date) -> Date? {
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: value) { return d }
        }
        if let d = ISO8601DateFormatter().date(from: value) { return d }
        return TaskInputParser.parse(value, now: now).dueDate
    }

    /// The persisted spelling ("daily", "everyNDays:3", "monthly:15") or any
    /// localized phrase ("har kuni", "every 3 days", "weekly").
    private static func recurrence(_ value: String, now: Date) -> Recurrence {
        let direct = Recurrence(string: value.lowercased())
        if direct != .none { return direct }
        return TaskInputParser.parse(value, now: now).recurrence
    }

    private static func pomodoroKind(_ value: String) -> PomodoroKind? {
        switch value.lowercased() {
        case "small", "kichik":            return .small
        case "normal", "medium", "o'rtacha": return .normal
        case "big", "large", "katta":      return .big
        default: return nil
        }
    }

    private static func truthy(_ value: String) -> Bool {
        ["true", "yes", "x", "1", "ha", "done"].contains(value.lowercased())
    }

    private static func mergedNotes(_ existing: String, _ lines: [String]) -> String {
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty { return joined }
        return joined.isEmpty ? existing : existing + "\n" + joined
    }

    // MARK: - JSON

    private static func parseJSON(_ text: String, now: Date) -> [TaskItem] {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let objects: [[String: Any]]
        if let array = root as? [Any] {
            objects = array.compactMap { $0 as? [String: Any] }
        } else if let dict = root as? [String: Any] {
            if let array = dict["tasks"] as? [Any] {
                objects = array.compactMap { $0 as? [String: Any] }
            } else {
                objects = [dict]
            }
        } else {
            return []
        }
        return objects.compactMap { jsonTask($0, now: now) }
    }

    private static func jsonTask(_ raw: [String: Any], now: Date) -> TaskItem? {
        // Lowercase the keys so "dueDate"/"DueDate" both hit the alias table.
        let dict = Dictionary(raw.map { ($0.key.lowercased(), $0.value) },
                              uniquingKeysWith: { a, _ in a })
        guard let title = (dict["title"] as? String)?
            .trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }

        var t = TaskItem(title: title, createdAt: now)
        var notes: [String] = []
        for (alias, key) in keyAliases {
            guard let value = dict[alias] else { continue }
            switch key {
            case "tags":
                if let list = value as? [Any] {
                    t.tags = list.compactMap { $0 as? String }
                        .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
                        .filter { !$0.isEmpty }
                } else if let s = value as? String {
                    t.tags = tagList(s)
                }
            case "priority":
                if let n = value as? Int, (1...4).contains(n) {
                    t.priority = TaskPriority(rawValue: 4 - n)
                } else if let s = value as? String, let p = priority(s) {
                    t.priority = p
                }
            case "estimate":
                if let n = value as? Int, n > 0 { t.estimatedPomodoros = n }
                else if let s = value as? String { apply(key: key, value: s, to: &t, notes: &notes, now: now) }
            case "done":
                let flag = (value as? Bool) ?? ((value as? String).map(truthy) ?? false)
                if flag { t.isDone = true; t.completedAt = now }
            default:
                if let s = value as? String {
                    apply(key: key, value: s, to: &t, notes: &notes, now: now)
                }
            }
        }
        if let subs = dict["subtasks"] as? [Any] {
            t.subtasks = subs.compactMap(jsonSubtask)
        }
        t.notes = mergedNotes(t.notes, notes)
        return t
    }

    private static func jsonSubtask(_ raw: Any) -> Subtask? {
        if let s = raw as? String {
            let title = s.trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : Subtask(title: title)
        }
        guard let d = raw as? [String: Any],
              let title = (d["title"] as? String)?
                  .trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
        let estimate = (d["estimate"] as? Int) ?? (d["estimatedPomodoros"] as? Int)
        let done = (d["done"] as? Bool) ?? false
        let kind = (d["pomodoro"] as? String).flatMap(pomodoroKind)
        return Subtask(title: title, isDone: done,
                       estimatedPomodoros: (estimate.map { $0 > 0 ? $0 : nil }) ?? nil,
                       pomodoroKind: kind)
    }

    // MARK: - Templates (shown in Settings, copied to the clipboard)

    /// The Markdown shape: one `#` heading per task with quick-add tokens,
    /// optional `key: value` refinements, `- [ ]` subtasks, free-text notes.
    public static let markdownTemplate = """
    # Write the report p1 #deep-work @myproject ~4 tomorrow 15:00
    category: Work
    planned: today
    repeat: weekly
    pomodoro: big

    Any free line under a heading becomes the task's notes.

    - [ ] Outline ~1
    - [ ] Draft ~2 (big)
    - [x] Gather data

    # Read 20 pages p3 #reading every day ~1
    """

    /// The JSON shape: an array of task objects (a single object or
    /// `{"tasks": [...]}` also parse). All fields except `title` are optional.
    public static let jsonTemplate = """
    [
      {
        "title": "Write the report",
        "category": "Work",
        "project": "myproject",
        "tags": ["deep-work"],
        "priority": "P1",
        "due": "2026-07-20 15:00",
        "planned": "2026-07-20",
        "estimate": 4,
        "repeat": "weekly",
        "pomodoro": "big",
        "notes": "Optional free-form notes.",
        "subtasks": [
          { "title": "Outline", "estimate": 1 },
          { "title": "Draft", "estimate": 2, "pomodoro": "big" },
          { "title": "Gather data", "done": true }
        ]
      },
      { "title": "Read 20 pages", "priority": "P3", "repeat": "daily", "estimate": 1 }
    ]
    """
}
