import SwiftUI

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).tint(.white)
                .labelsHidden()
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
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