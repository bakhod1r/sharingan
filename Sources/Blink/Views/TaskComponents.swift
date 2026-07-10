import SwiftUI
import BlinkCore

/// The one tag pill used across the Tasks feature — composer, row meta, and the
/// editor. Deliberately **neutral** (no accent/category tint) so tags stop
/// competing with the category bar and the priority flag for color attention;
/// color in a row now means exactly one thing per channel. Pass `onRemove` to
/// get the editable variant (with an ✕); omit it for a read-only chip.
struct TaskTag: View {
    let tag: String
    var onRemove: (() -> Void)? = nil
    /// Custom label color (from the sidebar tag editor); nil keeps the chip
    /// neutral as designed.
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? (onRemove == nil ? Color.dsSecondary : Color.dsPrimary))
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .accessibilityLabel("Remove tag \(tag)")
            }
        }
        .foregroundStyle(onRemove == nil ? Color.dsSecondary : Color.dsPrimary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.dsFillStrong))
    }
}

/// A muted "+N" pill shown after a truncated tag list so a busy task reads as
/// "two tags and more" instead of silently dropping the rest.
struct TaskTagOverflow: View {
    let count: Int
    var body: some View {
        Text("+\(count)")
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.dsTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.dsFill))
    }
}

/// Priority flag menu (P1–P4) — one component shared by the task composer and the
/// editor, which previously carried near-identical copies that had already drifted.
struct PriorityMenu: View {
    @Binding var priority: BlinkCore.TaskPriority
    var body: some View {
        Menu {
            ForEach(BlinkCore.TaskPriority.allCases.reversed()) { p in
                Button { priority = p } label: {
                    Label(p.menuLabel,
                          systemImage: priority == p ? "checkmark"
                                       : (p == .none ? "flag.slash" : "flag.fill"))
                }
            }
        } label: {
            let hex = priority.colorHex
            HStack(spacing: 5) {
                Image(systemName: priority == .none ? "flag" : "flag.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(priority == .none ? "Priority" : priority.label)
                    .font(.system(.caption, design: .rounded).weight(.medium))
            }
            .foregroundStyle(hex.map { Color(hex: $0) } ?? Color.dsSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.dsFill))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}
