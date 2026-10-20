import AppKit
import PDFKit
import SwiftUI
import InvoiceCore

enum InvoicePDF {
    private static let ink = NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.16, alpha: 1)
    private static let muted = NSColor(calibratedWhite: 0.42, alpha: 1)
    private static let paperWidth: CGFloat = 595.28
    private static let paperHeight: CGFloat = 841.89

    static func render(_ invoice: Invoice, accentColor: InvoiceAccent = .standard,
                       defaultTemplate: InvoiceTemplate = .boringDefault01, pageCount: Int? = nil) -> Data {
        let t = invoice.documentLanguage.text
        let template = invoice.resolvedTemplate(default: defaultTemplate)
        if template == .mono01 || template == .manoloBay {
            return MonoInvoicePDF.render(invoice, template: template)
        }
        let accent = accentColor.textOnWhite.nsColor
        let bandText: NSColor = accentColor.usesDarkBandText ? .black : .white
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: paperWidth, height: paperHeight)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [kCGPDFContextTitle as String: "\(t("Faktúra")) \(invoice.number)", kCGPDFContextAuthor as String: invoice.supplier.name] as CFDictionary) else { return Data() }
        let left: CGFloat = 38
        let width: CGFloat = paperWidth - 76
        var page = 0
        var y: CGFloat = 0
        var paymentQR: PaymentQRImage?
        var paymentQRError: String?
        do {
            if let payment = try PaymentQR.make(for: invoice) { paymentQR = try PaymentQRImage(payment: payment) }
        } catch { paymentQRError = error.localizedDescription }

        func text(_ value: String, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, size: CGFloat = 9, weight: NSFont.Weight = .regular, color: NSColor = ink, alignment: NSTextAlignment = .left, monospaced: Bool = false) -> CGFloat {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = 2
            let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color, .paragraphStyle: paragraph]
            var string = InvoiceTypography.attributed(value, size: size, weight: weight, monospaced: monospaced, attributes: attributes)
            if monospaced, string.size().width > w {
                string = InvoiceTypography.attributed(value, size: size * w / string.size().width, weight: weight,
                                                       monospaced: true, attributes: attributes)
            }
            let h = ceil(string.boundingRect(with: NSSize(width: w, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            string.draw(with: NSRect(x: x, y: top, width: w, height: h + 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
            return h
        }
        func height(_ value: String, width: CGFloat, size: CGFloat = 9) -> CGFloat {
            let p = NSMutableParagraphStyle(); p.lineSpacing = 2
            return ceil(InvoiceTypography.attributed(value, size: size, attributes: [.paragraphStyle: p])
                .boundingRect(with: NSSize(width: width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        }
        func line(_ top: CGFloat) {
            NSColor(calibratedWhite: 0.87, alpha: 1).setFill()
            NSRect(x: left, y: top, width: width, height: 0.6).fill()
        }
        func picture(_ data: Data?, rect: NSRect) {
            guard let data, let image = NSImage(data: data), image.size.width > 0 else { return }
            let ratio = min(rect.width / image.size.width, rect.height / image.size.height)
            let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        func beginPage() {
            page += 1
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: paperHeight)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: paperWidth, height: paperHeight).fill()
            y = 40
        }
        func endPage() {
            let contacts = [invoice.supplier.website, invoice.supplier.email, invoice.supplier.phone].filter { !$0.isEmpty }
            let footerTop: CGFloat = invoice.logo == nil ? 784 : (contacts.count > 2 ? 760 : 770)
            line(footerTop)
            InvoiceFooterLayout.draw(issuer: invoice.issuedBy.isEmpty ? "" : "\(t("Vystavil")): \(invoice.issuedBy)",
                                     contacts: contacts, x: left, top: footerTop + 11, width: width, size: 7, color: muted)
            let logoSide: CGFloat = 67 * 0.4
            picture(invoice.logo, rect: NSRect(x: (paperWidth - logoSide) / 2, y: paperHeight - 12 - logoSide,
                                              width: logoSide, height: logoSide))
            _ = text("\(page)/\(pageCount ?? 1)", paperWidth - 70, 821, 32, size: 7, color: muted, alignment: .right, monospaced: true)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }
        func continued() {
            endPage(); beginPage()
            _ = text("\(t("Faktúra")) \(invoice.number)", left, y, width, size: 15, weight: .semibold)
            y += 37
        }
        func tableHeader() {
            NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
            NSRect(x: left, y: y, width: width, height: 27).fill()
            _ = text(t("POLOŽKA"), left + 9, y + 8, 240, size: 7, weight: .semibold, color: muted)
            _ = text(t("MNOŽSTVO"), 295, y + 8, 63, size: 7, weight: .semibold, color: muted, alignment: .right)
            _ = text(t("CENA / MJ"), 370, y + 8, 74, size: 7, weight: .semibold, color: muted, alignment: .right)
            _ = text(invoice.supplier.vatPayer ? t("SPOLU S DPH") : t("SPOLU"), 459, y + 8, 88, size: 7, weight: .semibold, color: muted, alignment: .right)
            y += 27
        }
        func company(_ label: String, _ company: Company, x: CGFloat, top: CGFloat, w: CGFloat) -> CGFloat {
            _ = text(label, x, top, w, size: 8, weight: .semibold, color: accent)
            var cursor = top + 16
            cursor += text(company.name, x, cursor, w, size: 13, weight: .semibold) + 5
            cursor += text(company.address, x, cursor, w, size: 9) + 8
            let ids = [(t("IČO"), company.companyID), (t("DIČ"), company.taxID), (t("IČ DPH"), company.vatID)].filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            cursor += text(ids, x, cursor, w, size: 8.5, color: muted)
            return cursor
        }

        beginPage()
        let numberLeft = left + width - 400
        _ = text(t("FAKTÚRA"), left, 64, numberLeft - left - 12, size: 10, weight: .semibold, color: accent)
        let numberHeight = text(invoice.number, numberLeft, 56.5, 400, size: 21.75, weight: .semibold, alignment: .right, monospaced: true)
        y = max(112, 62 + numberHeight)
        line(y - 16)
        let supplierBottom = company(t("DODÁVATEĽ"), invoice.supplier, x: left, top: y, w: 237)
        let customerBottom = company(t("ODBERATEĽ"), invoice.customer, x: 317, top: y, w: 240)
        y = max(supplierBottom, customerBottom) + 11
        if !invoice.supplier.registration.isEmpty { y += text(invoice.supplier.registration, left, y, width, size: 7, color: muted) + 10 }
        line(y); y += 12
        let dates: [(String, String, Bool)] = [(t("Dátum vystavenia"), Format.date(invoice.issueDate), true), (t("Dátum splatnosti"), Format.date(invoice.dueDate), true), (t("Dátum dodania"), invoice.deliveryDate.map(Format.date) ?? "", true), (t("Forma úhrady"), t(invoice.paymentMethod), false), (t("Objednávka"), invoice.orderNumber, true)].filter { !$0.1.isEmpty }
        let columns = min(4, dates.count)
        let cellWidth = width / CGFloat(columns)
        for rowStart in stride(from: 0, to: dates.count, by: columns) {
            var rowHeight: CGFloat = 31
            for (column, pair) in dates[rowStart..<min(rowStart + columns, dates.count)].enumerated() {
                let x = left + CGFloat(column) * cellWidth
                let labelHeight = text(pair.0, x, y, cellWidth - 12, size: 7.5, color: muted)
                let valueHeight = text(pair.1, x, y + labelHeight + 5, cellWidth - 12, size: 9, weight: .medium, monospaced: pair.2)
                rowHeight = max(rowHeight, labelHeight + valueHeight + 11)
            }
            y += rowHeight
        }
        y += 5
        if let account = invoice.account {
            let bankText = Format.iban(account.iban) + (account.swift.isEmpty ? "" : "  /  \(account.swift)")
            y += text(bankText, left, y, width, size: 8.5) + 4
        }
        let symbols = [(t("Variabilný symbol"), invoice.variableSymbol), (t("Konštantný symbol"), invoice.constantSymbol), (t("Špecifický symbol"), invoice.specificSymbol)].filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }.joined(separator: "    ")
        y += text(symbols, left, y + 3, width, size: 8.5, weight: .medium) + 17
        if y > 675 { continued() }
        tableHeader()
        for item in invoice.items {
            let extra = [item.detail, item.discount > 0 ? "\(t("Zľava")) \(Format.number(item.discount)) %" : "", invoice.supplier.vatPayer ? "\(t("DPH")) \(Format.number(item.vatRate)) %" : ""].filter { !$0.isEmpty }.joined(separator: "\n")
            // Split unusually long descriptions into page-sized paragraphs without dropping text.
            let full = item.name + (extra.isEmpty ? "" : "\n" + extra)
            var chunks: [String] = []
            var chunk = ""
            for word in full.components(separatedBy: .whitespacesAndNewlines).filter({ !$0.isEmpty }) {
                let candidate = chunk.isEmpty ? word : chunk + " " + word
                if height(candidate, width: 239) > 330, !chunk.isEmpty { chunks.append(chunk); chunk = word }
                else { chunk = candidate }
            }
            if !chunk.isEmpty { chunks.append(chunk) }
            if chunks.isEmpty { chunks = [" "] }
            for (part, description) in chunks.enumerated() {
                let rowHeight = max(35, height(description, width: 239) + 18)
                if y + rowHeight > 754 { continued(); tableHeader() }
                _ = text(description, left + 9, y + 9, 239, size: 9)
                if part == 0 {
                    _ = text("\(Format.number(item.quantity)) \(t(item.unit))", 293, y + 9, 65, size: 9, alignment: .right, monospaced: true)
                    _ = text(Format.money(item.unitPrice, currency: invoice.currency), 365, y + 9, 79, size: 9, alignment: .right, monospaced: true)
                    _ = text(Format.money(item.total(vatEnabled: invoice.supplier.vatPayer), currency: invoice.currency), 449, y + 9, 98, size: 9, weight: .medium, alignment: .right, monospaced: true)
                }
                y += rowHeight
                line(y)
            }
        }
        y += 14
        var summary: [(String, Decimal, Bool)] = []
        if invoice.supplier.vatPayer {
            summary.append((t("Základ dane"), invoice.net, false))
            let rates = Set(invoice.items.map(\.vatRate)).sorted()
            for rate in rates {
                let tax = invoice.items.filter { $0.vatRate == rate }.reduce(Decimal.zero) { $0 + $1.vat(enabled: true) }
                summary.append(("\(t("DPH")) \(Format.number(rate)) %", tax, false))
            }
        }
        summary += [(t("Celková suma"), invoice.total, true), (t("Uhradené"), invoice.paid, false), (t("Suma na úhradu"), invoice.remaining, true)]
        if invoice.overpayment > 0 { summary.append((t("Preplatok"), invoice.overpayment, false)) }
        let summaryHeight = CGFloat(summary.count) * 22
        let note = [invoice.note.isEmpty ? "" : "\(t("Poznámka")): \((invoice.note == "Nie sme platiteľmi DPH." ? t(invoice.note) : invoice.note))", paymentQRError ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        let noteHeight = note.isEmpty ? 0 : height(note, width: 231, size: 8)
        let shortNote = noteHeight < 160
        let signatureHeight: CGFloat = invoice.signature == nil ? 0 : 80
        // Reserve the entire closing block so the payment band cannot become an orphan page.
        let qrHeight: CGFloat = paymentQR == nil ? 0 : PaymentQRImage.blockHeight
        let leftHeight = (shortNote && !note.isEmpty ? noteHeight + 7 : 0) + qrHeight
        let closingHeight = max(summaryHeight + 10 + signatureHeight, leftHeight) + 64
        if y + closingHeight > 754 { continued() }
        let totalsStart = y
        for row in summary {
            _ = text(row.0, 295, y + 3, 125, size: row.2 ? 10 : 9, weight: row.2 ? .semibold : .regular)
            _ = text(Format.money(row.1, currency: invoice.currency), 418, y + 3, 129, size: row.2 ? 12 : 9, weight: row.2 ? .semibold : .regular, color: row.0 == t("Suma na úhradu") ? accent : ink, alignment: .right, monospaced: true)
            y += 22
        }
        var noteBottom = totalsStart
        if !note.isEmpty {
            if shortNote {
                noteBottom += text(note, left, totalsStart + 3, 231, size: 8, color: muted) + 3
            } else {
                y = max(y, totalsStart + summaryHeight) + 18
                var chunk = ""
                for word in note.components(separatedBy: .whitespacesAndNewlines) {
                    if height(chunk + " " + word, width: width, size: 8) > 130 {
                        if y + 145 > 754 { continued() }
                        y += text(chunk, left, y, width, size: 8, color: muted) + 10
                        chunk = word
                    } else { chunk += (chunk.isEmpty ? "" : " ") + word }
                }
                if y + height(chunk, width: width, size: 8) > 754 { continued() }
                y += text(chunk, left, y, width, size: 8, color: muted) + 10
                noteBottom = y
            }
        }
        var closingTop = y + 10
        if !shortNote { closingTop = max(y, noteBottom) + 10 }
        if closingTop + max(signatureHeight, shortNote ? 0 : qrHeight) + 64 > 754 { continued(); closingTop = y; noteBottom = y }
        if let paymentQR {
            let qrTop = shortNote ? totalsStart + (note.isEmpty ? 0 : noteHeight + 7) : closingTop
            paymentQR.draw(at: NSPoint(x: left, y: qrTop))
            _ = text(paymentQR.payment.label, left, qrTop + PaymentQRImage.side + 1, PaymentQRImage.side, size: 8, weight: .semibold, alignment: .center)
            noteBottom = max(noteBottom, qrTop + qrHeight)
        }
        y = closingTop
        if invoice.signature != nil {
            _ = text(t("Podpis a pečiatka"), 346, y, 201, size: 7, color: muted)
            picture(invoice.signature, rect: NSRect(x: 359, y: y + 12, width: 170, height: 62))
            y += signatureHeight
        }
        y = max(y, noteBottom)
        accentColor.nsColor.setFill(); NSRect(x: left, y: y, width: width, height: 58).fill()
        let band = InvoicePaymentBand.columns(for: invoice, width: width, inset: 12, labelSize: 7, valueSize: 9.5, localized: true)
        NSColor.white.setFill()
        for x in InvoicePaymentBand.dividerPositions(band) {
            NSRect(x: left + x - 0.5, y: y, width: 1, height: 58).fill()
        }
        for column in band {
            _ = text(column.title, left + column.x, y + 11, column.width, size: 7, color: bandText)
            _ = text(column.value, left + column.x, y + 27, column.width, size: 9.5, weight: .semibold,
                     color: bandText, monospaced: column.monospaced)
        }
        endPage()
        context.closePDF()
        // A second pass writes final page counts directly into the PDF content.
        if pageCount == nil {
            return render(invoice, accentColor: accentColor, pageCount: page)
        }
        return output as Data
    }
}

final class PreviewPDFView: PDFView {
    var onResize: (() -> Void)?
    private var previousSize = CGSize.zero
    override func layout() {
        super.layout()
        guard bounds.size != previousSize else { return }
        previousSize = bounds.size
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}

final class PDFZoomControls: ObservableObject {
    enum Fit { case page, width }
    @Published private(set) var scale: CGFloat = 1
    private weak var view: PDFView?
    private var fit: Fit? = .page
    private var applyingFit = false
    private var observer: NSObjectProtocol?

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func attach(_ view: PreviewPDFView) {
        self.view = view
        view.onResize = { [weak self] in self?.applyFit() }
        observer = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !self.applyingFit { self.fit = nil }
            self.refreshScale()
        }
    }

    func fitTo(_ fit: Fit) {
        self.fit = fit
        applyFit()
    }

    func updateDocument(_ update: () -> Void) {
        // PDFKit also emits scale changes while replacing the document.
        applyingFit = true
        update()
        applyingFit = false
        DispatchQueue.main.async { [weak self] in self?.applyFit(); self?.refreshScale() }
    }

    func applyFit() {
        guard let view, let fit, let page = view.currentPage ?? view.document?.page(at: 0), view.bounds.width > 0, view.bounds.height > 0 else { return }
        let bounds = page.bounds(for: view.displayBox)
        let rotated = abs(page.rotation) % 180 == 90
        let width = rotated ? bounds.height : bounds.width
        let height = rotated ? bounds.width : bounds.height
        guard width > 0, height > 0 else { return }
        let widthScale = max(1, view.bounds.width - 32) / width
        let heightScale = max(1, view.bounds.height - 32) / height
        applyingFit = true
        view.scaleFactor = min(view.maxScaleFactor, max(view.minScaleFactor, fit == .page ? min(1, widthScale, heightScale) : widthScale))
        view.go(to: page)
        applyingFit = false
        refreshScale()
    }

    func zoom(by multiplier: CGFloat) { setScale((view?.scaleFactor ?? scale) * multiplier) }

    func setScale(_ value: CGFloat) {
        guard let view else { return }
        fit = nil
        view.scaleFactor = min(view.maxScaleFactor, max(view.minScaleFactor, value))
        refreshScale()
    }

    private func refreshScale() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let view = self.view, self.scale != view.scaleFactor else { return }
            self.scale = view.scaleFactor
        }
    }
}

struct PDFPreview: NSViewRepresentable {
    let data: Data
    let zoomControls: PDFZoomControls?
    func makeNSView(context: Context) -> PreviewPDFView {
        let view = PreviewPDFView()
        view.autoScales = zoomControls == nil
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(calibratedWhite: 0.91, alpha: 1)
        view.pageShadowsEnabled = true
        if let zoomControls {
            view.minScaleFactor = 0.25
            view.maxScaleFactor = 3
            zoomControls.attach(view)
        }
        return view
    }
    func updateNSView(_ view: PreviewPDFView, context: Context) {
        guard context.coordinator.data != data else { return }
        let page = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        let scale = view.scaleFactor
        let auto = view.autoScales
        context.coordinator.data = data
        let update = {
            view.document = PDFDocument(data: data)
            if auto { view.autoScales = true } else { view.scaleFactor = scale }
            if let target = view.document?.page(at: page) { view.go(to: target) }
        }
        if let zoomControls { zoomControls.updateDocument(update) } else { update() }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var data: Data? }
}

struct LivePreview: View {
    @EnvironmentObject private var store: Store
    let invoice: Invoice
    var showsZoomControls = false
    var accentOverride: InvoiceAccent? = nil
    var templateOverride: InvoiceTemplate? = nil
    @State private var data = Data()
    @StateObject private var zoom = PDFZoomControls()
    private var accent: InvoiceAccent { accentOverride ?? store.database.settings.invoiceAccent }
    private var template: InvoiceTemplate { templateOverride ?? invoice.resolvedTemplate(default: store.database.settings.defaultInvoiceTemplate) }
    var body: some View {
        VStack(spacing: 0) {
            PDFPreview(data: data, zoomControls: showsZoomControls ? zoom : nil)
            if showsZoomControls {
                Divider()
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    IconButton("Celá strana", "arrow.up.left.and.arrow.down.right") { zoom.fitTo(.page) }
                    IconButton("Prispôsobiť šírke", "arrow.left.and.right") { zoom.fitTo(.width) }
                    Divider().frame(height: 18).padding(.horizontal, 4)
                    IconButton("Oddialiť", "minus.magnifyingglass") { zoom.zoom(by: 1 / 1.2) }.disabled(zoom.scale <= 0.25)
                    BrandDropdown(title: "Priblíženie", value: "\(Int((zoom.scale * 100).rounded())) %", items: [25, 50, 75, 100, 125, 150, 200, 300].map { percent in
                        BrandDropdownItem(title: "\(percent) %", selected: Int((zoom.scale * 100).rounded()) == percent) { zoom.setScale(CGFloat(percent) / 100) }
                    }).frame(width: 90)
                    IconButton("Priblížiť", "plus.magnifyingglass") { zoom.zoom(by: 1.2) }.disabled(zoom.scale >= 3)
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
            .task(id: InvoicePreviewRequest(invoice: invoice, accent: accent, template: template)) {
                let request = InvoicePreviewRequest(invoice: invoice, accent: accent, template: template)
                do {
                    let rendered = try await InvoicePreviewRenderer.shared.data(for: request)
                    try Task.checkCancellation()
                    data = rendered
                } catch is CancellationError {
                    // A different tab or design superseded this preview.
                } catch { }
            }
    }
}
