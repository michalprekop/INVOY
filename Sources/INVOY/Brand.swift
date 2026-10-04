import SwiftUI
import AppKit

/// The same approved palette and vector artwork as the public website.
enum InvoyBrand {
    static let controlHeight: CGFloat = 40
    static let yellow = Color(red: 245 / 255, green: 1, blue: 54 / 255)
    static let ink = Color(red: 25 / 255, green: 26 / 255, blue: 23 / 255)
    static let canvas = Color(red: 233 / 255, green: 231 / 255, blue: 224 / 255)
    static let surface = Color(red: 248 / 255, green: 247 / 255, blue: 242 / 255)
    static let line = Color(red: 220 / 255, green: 218 / 255, blue: 210 / 255)

    static func image(_ name: String) -> NSImage {
        let bundled = Bundle.main.url(forResource: name, withExtension: "svg")
        // PDF verification and XCTest also use the approved artwork outside the app bundle.
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("web/public/brand/\(name).svg")
        return [bundled, source].compactMap { $0 }.compactMap { NSImage(contentsOf: $0) }.first ?? NSImage()
    }
}

struct BrandWordmark: View {
    var height: CGFloat = 30
    var body: some View {
        Image(nsImage: InvoyBrand.image("invoy-wordmark"))
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: height * 2.91246, height: height)
            .accessibilityLabel("INVOY.")
    }
}

struct BrandIcon: View {
    var size: CGFloat = 104
    var body: some View {
        Image(nsImage: InvoyBrand.image("invoy-icon-yellow"))
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: size, height: size).accessibilityLabel("INVOY.")
    }
}

struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(InvoyBrand.ink)
            .padding(.horizontal, size == .large ? 17 : 13)
            .frame(minHeight: InvoyBrand.controlHeight)
            .background(InvoyBrand.yellow, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(configuration.isPressed ? 0.08 : 0)))
            .opacity(enabled ? 1 : 0.45)
    }
}

struct BrandSearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
                .focused($focused)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .frame(height: InvoyBrand.controlHeight)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(focused ? InvoyBrand.ink : Color.gray.opacity(0.2)))
        .accessibilityElement(children: .contain)
    }
}

struct BrandDropdownItem {
    let title: String
    var symbol: String? = nil
    var selected = false
    var separatorBefore = false
    let action: () -> Void
}

struct BrandDropdown: View {
    let title: String
    let value: String
    var symbol: String? = nil
    var compact = false
    var valueFont: Font = .system(size: 13)
    let items: [BrandDropdownItem]
    @State private var opened = false
    @State private var width: CGFloat = 200
    @State private var focused: Int?
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        Button { opened.toggle() } label: {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 16)).accessibilityHidden(true)
                }
                Text(value).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, compact ? 4 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: compact ? 24 : InvoyBrand.controlHeight)
            .background(opened ? InvoyBrand.yellow : compact ? .clear : InvoyBrand.canvas, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).font(valueFont).foregroundStyle(InvoyBrand.ink)
        .accessibilityLabel(title).accessibilityValue(value).help(value)
        .background(GeometryReader { geometry in
            Color.clear.onAppear { width = geometry.size.width }
                .onChange(of: geometry.size.width) { _, next in width = next }
        })
        .popover(isPresented: $opened, arrowEdge: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            if item.separatorBefore { Divider().padding(.vertical, 4) }
                            BrandDropdownRow(item: item, highlighted: focused == index) {
                                opened = false
                                item.action()
                            }
                            .id(index)
                        }
                        if items.isEmpty { Text("Žiadne možnosti").foregroundStyle(.secondary).padding(12) }
                    }.padding(6)
                }
                .frame(width: max(200, min(width, 380)), height: min(280, CGFloat(max(items.count, 1)) * 40 + 12 + CGFloat(items.filter(\.separatorBefore).count) * 9))
                .background(Color.white)
                .focusable().focused($keyboardFocused).focusEffectDisabled()
                .onAppear {
                    focused = items.firstIndex(where: \.selected) ?? (items.isEmpty ? nil : 0)
                    keyboardFocused = true
                }
                .onChange(of: focused) { _, next in if let next { proxy.scrollTo(next) } }
                .onKeyPress(keys: [.return, .space, .downArrow, .upArrow]) { key in
                    guard !items.isEmpty else { return .ignored }
                    if key.key == .downArrow {
                        focused = min((focused ?? -1) + 1, items.count - 1)
                        return .handled
                    }
                    if key.key == .upArrow {
                        focused = max((focused ?? 1) - 1, 0)
                        return .handled
                    }
                    guard let focused, items.indices.contains(focused) else { return .ignored }
                    opened = false
                    items[focused].action()
                    return .handled
                }
                .onExitCommand { opened = false }
            }
            .environment(\.colorScheme, .light)
        }
    }
}

private struct BrandDropdownRow: View {
    let item: BrandDropdownItem
    let highlighted: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol = item.symbol {
                    Image(systemName: symbol).frame(width: 16).accessibilityHidden(true)
                }
                Text(item.title).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if item.selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
            }
            .font(.system(size: 13)).foregroundStyle(InvoyBrand.ink)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(hovering || highlighted || item.selected ? InvoyBrand.canvas : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).focusEffectDisabled()
            .onHover { hovering = $0 }
            .accessibilityAddTraits(item.selected ? .isSelected : [])
    }
}

struct BrandSegment: View {
    let title: String
    var symbol: String? = nil
    var iconOnly = true
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    if iconOnly { Image(systemName: symbol) }
                    else { Label(title, systemImage: symbol).lineLimit(1) }
                }
                else { Text(title).lineLimit(1) }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(InvoyBrand.ink)
            .padding(.horizontal, symbol == nil ? 12 : 10)
            .frame(maxWidth: .infinity, minHeight: InvoyBrand.controlHeight - 6, alignment: .center)
            .background(selected ? InvoyBrand.yellow : .clear, in: RoundedRectangle(cornerRadius: 7))
            // Plain buttons otherwise only hit-test the text/image of an inactive segment.
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct BrandIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(InvoyBrand.ink)
            .frame(width: InvoyBrand.controlHeight, height: InvoyBrand.controlHeight)
            .background(InvoyBrand.canvas, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(configuration.isPressed ? 0.06 : 0)))
            .opacity(enabled ? 1 : 0.45)
    }
}

/// Keep native list/table selection and keyboard handling, but use the app palette.
struct InvoiceSelectionBackground: NSViewRepresentable {
    let selected: Bool

    func makeNSView(context: Context) -> SelectionView { SelectionView() }
    func updateNSView(_ view: SelectionView, context: Context) {
        view.applyAppearance()
        view.needsDisplay = true
    }

    final class SelectionView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyAppearance()
        }

        override func viewWillDraw() {
            // SwiftUI resets reused rows while filtering/reloading. Apply after that
            // update, immediately before the native view hierarchy is drawn.
            applyAppearance()
            super.viewWillDraw()
        }

        func applyAppearance() {
            var ancestor = superview
            var row: NSTableRowView?
            while let view = ancestor {
                if let rowView = view as? NSTableRowView { row = rowView }
                if let table = view as? NSTableView {
                    if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
                    if let row {
                        let color = row.isSelected ? NSColor(InvoyBrand.canvas) : .clear
                        if row.backgroundColor != color {
                            row.backgroundColor = color
                            row.needsDisplay = true
                        }
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

private struct SettingsFormControlsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var settingsFormControls: Bool {
        get { self[SettingsFormControlsKey.self] }
        set { self[SettingsFormControlsKey.self] = newValue }
    }
}

struct FormInputStyle: ViewModifier {
    @Environment(\.settingsFormControls) private var branded
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        if branded {
            content.textFieldStyle(.plain).focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: InvoyBrand.controlHeight, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? InvoyBrand.ink : InvoyBrand.canvas))
        } else { content.textFieldStyle(.roundedBorder) }
    }
}

struct BrandSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(InvoyBrand.ink).padding(.horizontal, 13)
            .frame(minHeight: InvoyBrand.controlHeight)
            .background(configuration.isPressed ? InvoyBrand.canvas : Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(InvoyBrand.canvas))
    }
}
