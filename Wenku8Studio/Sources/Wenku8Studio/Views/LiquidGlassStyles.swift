import SwiftUI

struct GlassInputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }
}

struct GlassSegmentedControl<SelectionValue: Hashable & Identifiable>: View where SelectionValue: RawRepresentable, SelectionValue.RawValue == String {
    @Binding var selection: SelectionValue
    let items: [SelectionValue]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(items) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }
}
