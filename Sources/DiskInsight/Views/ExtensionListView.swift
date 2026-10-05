import SwiftUI

struct ExtensionListView: View {
    @EnvironmentObject private var model: AppModel

    private var total: Int64 {
        model.root?.value(model.sizeMode) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("File types")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.selectedExtension != nil {
                    Button("Clear") { model.selectedExtension = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.link)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if model.extensions.isEmpty {
                VStack {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.extensions, selection: extensionSelection) { stat in
                    row(stat)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .tag(stat.index)
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 20)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var extensionSelection: Binding<Int32?> {
        Binding(get: { model.selectedExtension },
                set: { model.selectedExtension = $0 })
    }

    private func row(_ stat: ExtensionStat) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.swiftUIColor(stat.colorIndex))
                .frame(width: 10, height: 10)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.18)))
            Text(stat.displayName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.count(stat.count))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text(Format.bytes(stat.value(model.sizeMode)))
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            Text(Format.percent(total > 0 ? Double(stat.value(model.sizeMode)) / Double(total) : 0))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
        .font(.system(size: 11))
        .frame(height: 20)
        .contentShape(Rectangle())
    }
}
