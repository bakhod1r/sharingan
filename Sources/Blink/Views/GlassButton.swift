import SwiftUI

struct GlassButton: View {
    var label: String
    var systemImage: String
    var tint: Color = .white
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .glassCapsule(material: .regular)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .disabled(!isEnabled)
        .buttonStyle(.pressable)
    }
}