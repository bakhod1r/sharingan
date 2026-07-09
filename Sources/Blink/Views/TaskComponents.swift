import SwiftUI

/// The one tag pill used across the Tasks feature — composer, row meta, and the
/// editor. Deliberately **neutral** (no accent/category tint) so tags stop
/// competing with the category bar and the priority flag for color attention;
/// color in a row now means exactly one thing per channel. Pass `onRemove` to
/// get the editable variant (with an ✕); omit it for a read-only chip.
struct TaskTag: View {
    let tag: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
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
