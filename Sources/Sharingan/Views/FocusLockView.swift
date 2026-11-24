import SwiftUI
import SharinganCore

/// Full-screen reminder shown when the user leaves the task's allowed apps.
struct FocusLockView: View {
    let lock: FocusLock
    let backTarget: BlockedApp?
    let onBack: () -> Void
    let onSnooze: () -> Void
    let onStop: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
            VStack(spacing: DS.Space.lg) {
                Text("Your task")
                    .font(.dsMicro)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Color.dsTertiary)
                Text(lock.taskTitle)
                    .font(.dsDisplay)
                    .foregroundStyle(Color.dsPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 640)
                Text("Stay focused — don't get distracted.")
                    .font(.dsBody)
                    .foregroundStyle(Color.dsSecondary)
                VStack(spacing: DS.Space.md) {
                    if let backTarget {
                        Button(action: onBack) {
                            Text("Back to \(backTarget.name)")
                                .font(.dsHeadline)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, DS.Space.xl)
                                .padding(.vertical, DS.Space.md)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: DS.Space.md) {
                        secondary("Allow 5 min", action: onSnooze)
                        secondary("Stop session", action: onStop)
                    }
                }
                .padding(.top, DS.Space.lg)
            }
            .padding(DS.Space.xl)
        }
        .ignoresSafeArea()
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dsCallout)
                .foregroundStyle(Color.dsPrimary)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.sm)
                .background(Color.dsFillStrong, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).stroke(Color.dsHairline))
        }
        .buttonStyle(.plain)
    }
}
