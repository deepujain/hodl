import SwiftUI

/// A titled card of rows with a short note under it, in the style of the panel.
struct SettingsCard<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: title)
            VStack(spacing: 0, content: content)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let note {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// The line between two rows of a card, starting after the symbols.
struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 48) }
}

/// One row: a tinted symbol, a title with an optional line under it, and a control on the right.
/// Choices that need room sit under the title instead.
struct SettingRow<Trailing: View, Below: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    var tint: Color = .accentColor
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var below: () -> Below
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title)
                            .font(.system(size: 12.5, weight: .medium))
                        if let detail {
                            Text(verbatim: detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailing()
                }
                .frame(minHeight: 24)
                below()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

extension SettingRow where Below == EmptyView {
    init(symbol: String, title: String, detail: String? = nil, tint: Color = .accentColor, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(symbol: symbol, title: title, detail: detail, tint: tint, trailing: trailing) { EmptyView() }
    }
}

/// A row whose choices show as pills under its title.
struct ChoiceRow<Value: Hashable>: View {
    let symbol: String
    let title: String
    var detail: String?
    var tint: Color = .accentColor
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        SettingRow(symbol: symbol, title: title, detail: detail, tint: tint, trailing: { EmptyView() }) {
            ChoicePills(options: options, selection: $selection)
        }
    }
}

/// A row with a switch.
struct SwitchRow: View {
    let symbol: String
    let title: String
    var detail: String?
    var tint: Color = .accentColor
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(symbol: symbol, title: title, detail: detail, tint: tint) {
            PillSwitch(isOn: $isOn, label: title)
        }
    }
}

/// A switch drawn in SwiftUI, so it matches the pills and renders anywhere.
struct PillSwitch: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.3)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

/// A small capsule button for actions in a row.
struct RowButton: View {
    let title: String
    var destructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(destructive ? Color.red : Color.accentColor)
                .background((destructive ? Color.red : Color.accentColor).opacity(0.12), in: Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Every option visible at once, as pills; the chosen one filled.
struct ChoicePills<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                let chosen = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(verbatim: option.label)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(chosen ? Color.white : Color.primary)
                        .background(chosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.8)), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The tabs across the top, as chips with a symbol over the name.
struct SettingsTabs<Tab: Hashable>: View {
    let tabs: [(tab: Tab, title: String, symbol: String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.tab) { item in
                let chosen = item.tab == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = item.tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 14, weight: .semibold))
                        Text(verbatim: item.title).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                    }
                    .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(chosen ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(chosen ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1.2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
