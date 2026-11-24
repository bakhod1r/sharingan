import SwiftUI
import AppKit
import SharinganCore

/// One installed application, as the block-app picker lists it.
struct InstalledApp: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage
}

/// Enumerates every application the picker can offer: /Applications (top
/// level plus one folder deep, for Utilities-style subfolders),
/// /System/Applications, ~/Applications, and whatever is currently running
/// with a Dock presence. Deduped by bundle id, sorted by display name.
enum InstalledAppsCatalog {
    @MainActor
    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        var found: [String: InstalledApp] = [:]

        func add(_ url: URL) {
            guard url.pathExtension == "app",
                  let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier,
                  found[id] == nil,
                  id != Bundle.main.bundleIdentifier else { return }
            // Bundle display name first; the filename fallback drops ".app"
            // (FileManager.displayName keeps the extension unless Finder is
            // set to hide it).
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 20, height: 20)
            found[id] = InstalledApp(bundleID: id, name: name, icon: icon)
        }

        let roots = ["/Applications", "/System/Applications",
                     (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        for root in roots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard let entries = try? fm.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { continue }
            for entry in entries {
                if entry.pathExtension == "app" {
                    add(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                            .isDirectory == true,
                          let sub = try? fm.contentsOfDirectory(
                            at: entry, includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles]) {
                    sub.forEach(add)
                }
            }
        }
        // Running Dock apps too — catches things installed anywhere else.
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            if let url = app.bundleURL { add(url) }
        }
        return found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

/// The full installed-app list for the blocker: tap Block to add an app to
/// the blocked list (enabled), tap again to take it back out. Search narrows.
/// Opened from Settings → Focus → App blocking, and from the task editor
/// (`.allow` mode) to pick a task's allowed apps.
enum AppPickerMode {
    case block, allow

    var title: String { self == .block ? "Block apps" : "Allowed apps" }
    var addLabel: String { self == .block ? "Block" : "Allow" }
    var doneLabel: String { self == .block ? "Blocked" : "Allowed" }
    var footnote: String {
        switch self {
        case .block:
            return "Blocked apps close on a break — and during focus sessions when “Block apps during focus” is on."
        case .allow:
            return "During a focus session on this task, any other app is covered by a reminder."
        }
    }
}

struct BlockAppPickerSheet: View {
    @Binding var apps: [BlockedApp]
    let mode: AppPickerMode
    @Environment(\.dismiss) private var dismiss
    @State private var installed: [InstalledApp] = []
    @State private var query = ""

    private var shown: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return installed }
        return installed.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(mode.title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))

            if installed.isEmpty {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else if shown.isEmpty {
                Spacer()
                Text("No apps match the search")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { app in
                            row(app)
                        }
                    }
                }
            }

            Text(mode.footnote)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 440, height: 540)
        .task { installed = InstalledAppsCatalog.scan() }
    }

    private func row(_ app: InstalledApp) -> some View {
        let blocked = apps.contains { $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame }
        return HStack(spacing: 10) {
            Image(nsImage: app.icon)
            Text(app.name)
                .font(.system(.callout, design: .rounded))
                .lineLimit(1)
            Spacer()
            Button {
                if blocked {
                    apps.removeAll { $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame }
                } else {
                    apps.append(BlockedApp(bundleID: app.bundleID, name: app.name))
                }
            } label: {
                Label(blocked ? mode.doneLabel : mode.addLabel,
                      systemImage: blocked ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(blocked ? Color.green : Color.secondary)
                    .frame(width: 84)
            }
            .buttonStyle(.pressableSubtle)
            .help(mode == .block
                  ? (blocked ? "Take \(app.name) off the blocked list" : "Block \(app.name)")
                  : (blocked ? "Take \(app.name) off the allowed list" : "Allow \(app.name)"))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(blocked ? Color.green.opacity(0.10) : Color.clear)
        )
    }
}
