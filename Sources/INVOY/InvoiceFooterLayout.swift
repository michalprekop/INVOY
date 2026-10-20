import AppKit

/// Shared three-column footer for every PDF template, matching the invoice editor.
enum InvoiceFooterLayout {
    static func draw(issuer: String, contacts: [String], x: CGFloat, top: CGFloat,
                     width: CGFloat, size: CGFloat, color: NSColor, monospaced: Bool = false) {
        let gap: CGFloat = 12
        let columnWidth = (width - 2 * gap) / 3
        func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat, size: CGFloat,
                  alignment: NSTextAlignment = .left, mono: Bool = false) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineSpacing = 2
            paragraph.lineBreakMode = .byWordWrapping
            let string = InvoiceTypography.attributed(value, size: size, monospaced: mono,
                attributes: [.foregroundColor: color, .paragraphStyle: paragraph])
            let height = ceil(string.boundingRect(with: NSSize(width: width, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            string.draw(with: NSRect(x: x, y: top, width: width, height: height + 2),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        text(issuer, x: x, top: top, width: columnWidth, size: size, mono: monospaced)
        text(contacts.filter { !$0.isEmpty }.joined(separator: "\n"),
             x: x + columnWidth + gap, top: top, width: columnWidth, size: size,
             alignment: .center, mono: monospaced)

        let brandWidth: CGFloat = 42
        let logoHeight: CGFloat = 12
        let logo = InvoyBrand.image("invoy-wordmark")
        let logoWidth = logoHeight * logo.size.width / max(1, logo.size.height)
        let brandX = x + width - brandWidth
        logo.draw(
            in: NSRect(x: brandX + (brandWidth - logoWidth) / 2, y: top, width: logoWidth, height: logoHeight),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        text("www.invoy.xyz", x: brandX, top: top + logoHeight + 3,
             width: brandWidth, size: 5, alignment: .center, mono: monospaced)
    }
}
