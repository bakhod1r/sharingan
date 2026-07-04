import SwiftUI

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(.green)
                .labelsHidden()
                .controlSize(.small)
        }
        .frame(minHeight: 24)
    }
}

struct DarkGlassFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12).padding(.vertical, 10)
            .foregroundStyle(.white)
            .glassRounded(14, material: .thin)
    }
}