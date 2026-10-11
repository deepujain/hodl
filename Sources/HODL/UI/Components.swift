import SwiftUI

/// A round Control Center–style switch, as in Where’d It Go.
struct QuickSwitch: View {
    let symbol: String
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    let help: LocalizedStringKey

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { isOn.toggle() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.75))
                    .frame(width: 34, height: 34)
                    .background(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

/// A small square tile in the panel’s card.
struct Tile<Accessory: View>: View {
    let symbol: String
    let title: String
    let value: String
    var tint: Color = .secondary
    var dimmed = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                    .frame(width: 16, alignment: .leading)
                Spacer(minLength: 0)
                accessory()
            }
            Spacer(minLength: 0)
            Text(verbatim: title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(dimmed ? .secondary : .primary)
                .lineLimit(1)
            Text(verbatim: value)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .leading)
        .background(.background.opacity(dimmed ? 0.35 : 0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

extension Tile where Accessory == EmptyView {
    init(symbol: String, title: String, value: String, tint: Color = .secondary, dimmed: Bool = false) {
        self.init(symbol: symbol, title: title, value: value, tint: tint, dimmed: dimmed) { EmptyView() }
    }
}

struct StatusDot: View {
    let state: AgentState

    var color: Color {
        switch state {
        case .active: .green
        case .idle: .orange
        case .detected: .blue
        case .off: .secondary.opacity(0.4)
        }
    }

    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
            .shadow(color: state == .active ? .green.opacity(0.6) : .clear, radius: 3)
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(verbatim: title.uppercased())
            Spacer()
            if let trailing { Text(verbatim: trailing) }
        }
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }
}

struct FooterIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 26)
            .contentShape(Rectangle())
    }
}

struct FooterButton: View {
    let symbol: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { FooterIcon(symbol: symbol) }
            .buttonStyle(FooterButtonStyle())
            .help(Text(title))
            .accessibilityLabel(Text(title))
    }
}

struct FooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hovering in
            configuration.label
                .foregroundStyle(.secondary)
                .opacity(isEnabled ? 1 : 0.4)
                .background(.primary.opacity(configuration.isPressed ? 0.14 : hovering && isEnabled ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

struct Hovering<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    // `@State` is a macro that needs SwiftUI’s plugin, which the Command Line Tools don’t ship.
    private let hoverState = State(initialValue: false)

    var body: some View {
        content(hoverState.wrappedValue).onHover { hoverState.wrappedValue = $0 }
    }
}

/// The app icon, drawn small for headers.
struct HODLMark: View {
    var size: CGFloat = 34

    var body: some View {
        AppIconArtwork(showsPill: false)
            .scaleEffect(size / 824, anchor: .center)
            .frame(width: size, height: size)
            .clipped()
            .accessibilityHidden(true)
    }
}
