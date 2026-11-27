import SwiftUI
import SharinganCore

struct ReminderRow: View {
    @Binding var item: ReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(.white.opacity(0.85))
                GlassMenuPicker(selection: $item.kind,
                                cases: ReminderItem.Kind.allCases, label: { $0.label })
                Spacer()
                Toggle("", isOn: $item.enabled).toggleStyle(.glassSwitch(tint: .green)).labelsHidden()
            }
            HStack {
                Text("Every \(item.intervalMinutes) min").foregroundStyle(.white.opacity(0.8))
                Spacer()
                DSStepper(value: $item.intervalMinutes, range: 1...300)
            }
            TextField("Message", text: $item.message, axis: .vertical)
                .textFieldStyle(DarkGlassFieldStyle())
                .lineLimit(1...3)
        }
        .padding(.vertical, 6)
    }
}