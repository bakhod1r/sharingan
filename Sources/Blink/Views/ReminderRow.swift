import SwiftUI
import BlinkCore

struct ReminderRow: View {
    @Binding var item: ReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(.white.opacity(0.85))
                Picker("Kind", selection: $item.kind) {
                    ForEach(ReminderItem.Kind.allCases, id: \.self) { k in
                        Text(k.label).tag(k)
                    }
                }
                .pickerStyle(.menu).tint(.white)
                Spacer()
                Toggle("", isOn: $item.enabled).tint(.white).labelsHidden()
            }
            HStack {
                Text("Every").foregroundStyle(.white.opacity(0.8))
                Stepper("\(item.intervalMinutes) min", value: $item.intervalMinutes, in: 1...300)
                    .tint(.white)
            }
            TextField("Message", text: $item.message, axis: .vertical)
                .textFieldStyle(DarkGlassFieldStyle())
                .lineLimit(1...3)
        }
        .padding(.vertical, 6)
    }
}