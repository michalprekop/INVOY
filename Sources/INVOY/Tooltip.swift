import AppKit
import SwiftUI

extension View {
    func instantTooltip(_ text: String?) -> some View {
        modifier(InstantTooltipModifier(text: text))
    }
}

private struct InstantTooltipModifier: ViewModifier {
    let text: String?
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchor(text: text, visible: hovering))
            .onHover { hovering = $0 }
    }
}

private struct TooltipAnchor: NSViewRepresentable {
    let text: String?
    let visible: Bool

    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) {
        if visible, let text, !text.isEmpty {
            TooltipPresenter.shared.show(text, at: view)
        } else {
            TooltipPresenter.shared.hide(for: view)
        }
    }
    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        TooltipPresenter.shared.hide(for: view)
    }

    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { TooltipPresenter.shared.hide(for: self) }
        }
    }
}

/// A separate non-interactive panel keeps hints visible outside scroll views and popovers.
@MainActor
final class TooltipPresenter {
    static let shared = TooltipPresenter()
    private(set) var panel: NSPanel?
    private weak var anchor: NSView?
    private var monitor: Any?

    func show(_ text: String, at view: NSView) {
        guard let window = view.window else { return }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        guard rect.width > 0, rect.height > 0 else { return }
        if anchor === view, (panel?.contentView as? TooltipBubble)?.text == text { return }
        hide()
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? rect
        let bubble = TooltipBubble(text: text, maxWidth: min(320, screen.width - 16))
        let size = bubble.frame.size
        let x = max(screen.minX + 8, min(rect.midX - size.width / 2, screen.maxX - size.width - 8))
        let above = rect.minY - size.height - 8 < screen.minY && rect.maxY + size.height + 8 < screen.maxY
        let y = above ? rect.maxY + 8 : rect.minY - size.height - 8
        bubble.arrowX = rect.midX - x
        bubble.above = above
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = bubble
        self.panel = panel
        anchor = view
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            self?.hide()
            return event
        }
    }

    func hide(for view: NSView? = nil) {
        if let view, anchor !== view { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        anchor = nil
    }
}

private final class TooltipBubble: NSView {
    let text: String
    var arrowX: CGFloat = 0
    var above = false
    private let attributes: [NSAttributedString.Key: Any]

    init(text: String, maxWidth: CGFloat) {
        self.text = text
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        attributes = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                      .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
        let bounds = (text as NSString).boundingRect(with: NSSize(width: maxWidth - 20, height: 1000),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(bounds.width) + 20, height: ceil(bounds.height) + 22))
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 25 / 255, green: 26 / 255, blue: 23 / 255, alpha: 1).setFill()
        let body = NSRect(x: 0, y: above ? 6 : 0, width: bounds.width, height: bounds.height - 6)
        NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6).fill()
        let arrow = NSBezierPath()
        let baseY = above ? body.minY : body.maxY
        arrow.move(to: NSPoint(x: arrowX - 6, y: baseY))
        arrow.line(to: NSPoint(x: arrowX, y: above ? 0 : bounds.height))
        arrow.line(to: NSPoint(x: arrowX + 6, y: baseY))
        arrow.close()
        arrow.fill()
        (text as NSString).draw(with: body.insetBy(dx: 10, dy: 8),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }
}
