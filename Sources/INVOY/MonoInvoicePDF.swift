import AppKit
import InvoiceCore

/// Independent layout keeps the original template unchanged.
enum MonoInvoicePDF {
    static func render(_ invoice: Invoice, template: InvoiceTemplate = .mono01, pageCount: Int? = nil) -> Data {
        let t = invoice.documentLanguage.text
        let manolo = template == .manoloBay
        let compact = invoice.items.count > 1
        let output = NSMutableData()
        let pageWidth: CGFloat = 595.28, pageHeight: CGFloat = 841.89
        let left: CGFloat = 32, width: CGFloat = 531.28, bottom: CGFloat = 752
        let ink = NSColor(calibratedWhite: 0.08, alpha: 1)
        let muted = NSColor(calibratedWhite: 0.44, alpha: 1)
        var box = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box,
                                      [kCGPDFContextTitle as String: "\(t("Faktúra")) \(invoice.number)",
                                       kCGPDFContextAuthor as String: invoice.supplier.name] as CFDictionary) else { return Data() }
        var y: CGFloat = 0, page = 0
        var qr: PaymentQRImage?
        var qrError = ""
        do {
            if let payment = try PaymentQR.make(for: invoice) { qr = try PaymentQRImage(payment: payment) }
        } catch { qrError = error.localizedDescription }

        func attributed(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular,
                        color: NSColor? = nil, alignment: NSTextAlignment = .left) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineSpacing = 2
            paragraph.lineBreakMode = .byWordWrapping
            return InvoiceTypography.attributed(value, size: size, weight: weight, monospaced: !manolo,
                attributes: [.foregroundColor: color ?? ink, .paragraphStyle: paragraph])
        }
        func height(_ value: String, _ w: CGFloat, size: CGFloat = 8.5, weight: NSFont.Weight = .regular) -> CGFloat {
            guard !value.isEmpty else { return 0 }
            return ceil(attributed(value, size: size, weight: weight)
                .boundingRect(with: NSSize(width: w, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        }
        @discardableResult func text(_ value: String, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat,
                                    size: CGFloat = 8.5, weight: NSFont.Weight = .regular,
                                    color: NSColor? = nil, alignment: NSTextAlignment = .left) -> CGFloat {
            let h = height(value, w, size: size, weight: weight)
            attributed(value, size: size, weight: weight, color: color, alignment: alignment)
                .draw(with: NSRect(x: x, y: top, width: w, height: h + 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
            return h
        }
        func rule(_ top: CGFloat, heavy: Bool = false) {
            if heavy {
                ink.setFill()
                NSRect(x: left, y: top, width: width, height: manolo ? 1.5 : 8).fill()
            } else {
                context.saveGState()
                context.setStrokeColor((manolo ? NSColor(calibratedWhite: 0.82, alpha: 1) : .black).cgColor)
                context.setLineWidth(0.5)
                context.setLineDash(phase: 0, lengths: manolo ? [] : [3, 2])
                context.move(to: CGPoint(x: left, y: top + 0.25))
                context.addLine(to: CGPoint(x: left + width, y: top + 0.25))
                context.strokePath()
                context.restoreGState()
            }
        }
        func picture(_ data: Data?, _ rect: NSRect) {
            guard let data, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return }
            let scale = min(rect.width / image.size.width, rect.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                 width: size.width, height: size.height), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        }
        func beginPage() {
            page += 1
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: pageHeight); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            NSColor.white.setFill(); box.fill()
            y = 32
        }
        func endPage() {
            let footerTop: CGFloat = manolo ? pageHeight - 50 : 774
            rule(footerTop)
            let issuer = manolo ? "\(t("Vystavil")): Dominika Vašek" : (invoice.issuedBy.isEmpty ? "" : "\(t("Vystavil")): \(invoice.issuedBy)")
            let contacts = manolo ? Array(ManoloInvoiceBrand.contacts.dropFirst()) :
                [invoice.supplier.website, invoice.supplier.email, invoice.supplier.phone]
            InvoiceFooterLayout.draw(issuer: issuer, contacts: contacts, x: left, top: footerTop + 10,
                                     width: width, size: 6.5, color: muted, monospaced: !manolo)
            text("\(page)/\(pageCount ?? 1)", left + width - 40, 825, 40, size: 6.5, color: muted, alignment: .right)
            NSGraphicsContext.restoreGraphicsState(); context.restoreGState(); context.endPDFPage()
        }
        func continued() {
            endPage(); beginPage()
            y += text("\(t("FAKTÚRA")) / \(invoice.number)", left, y, width, size: 14, weight: .bold) + 18
        }
        func ensure(_ h: CGFloat) { if y + h > bottom { continued() } }
        func tableHeader() {
            rule(y, heavy: true); y += manolo ? 11 : 17
            text(t("POLOŽKA"), left, y, 240, size: 7, color: muted)
            text(t("MNOŽSTVO"), 290, y, 62, size: 7, color: muted, alignment: .right)
            text(t("CENA / MJ"), 361, y, 92, size: 7, color: muted, alignment: .right)
            text(invoice.supplier.vatPayer ? t("SPOLU S DPH") : t("SPOLU"), 462, y, 101, size: 7, color: muted, alignment: .right)
            y += 18; rule(y)
        }
        func company(_ title: String, _ company: Company, x: CGFloat, top: CGFloat) -> CGFloat {
            let w: CGFloat = 253
            var cursor = top
            cursor += text(title, x, cursor, w, size: 7.5, color: muted) + (manolo && compact ? 4 : 7)
            cursor += text(company.name, x, cursor, w, size: 10, weight: .bold) + 6
            cursor += text(company.address, x, cursor, w) + (manolo && compact ? 4 : 7)
            let ids = [(t("IČO"), company.companyID), (t("DIČ"), company.taxID), (t("IČ DPH"), company.vatID)]
            for (label, value) in ids where !value.isEmpty {
                cursor += text(label + ": " + value, x, cursor, w, size: 8) + 2
            }
            return cursor
        }
        func detailRows(_ rows: [(String, String)], x: CGFloat, top: CGFloat) -> CGFloat {
            var cursor = top
            for (label, value) in rows where !value.isEmpty {
                let labelHeight = text(label, x, cursor, 96, size: 7.5, color: muted)
                let valueHeight = text(value, x + 102, cursor, 151, size: 8)
                cursor += max(labelHeight, valueHeight) + (manolo && compact ? 3 : 5)
            }
            return cursor
        }
        // Preserve paragraph breaks and split even an unbroken long word across pages.
        func chunks(_ value: String, w: CGFloat, maxHeight: CGFloat, size: CGFloat = 8.5) -> [String] {
            var result: [String] = [], chunk = ""
            for paragraph in value.components(separatedBy: "\n") {
                if !chunk.isEmpty { chunk += "\n" }
                for word in paragraph.components(separatedBy: " ") {
                    let separator = chunk.isEmpty || chunk.hasSuffix("\n") ? "" : " "
                    if height(chunk + separator + word, w, size: size) <= maxHeight { chunk += separator + word; continue }
                    if !chunk.isEmpty { result.append(chunk); chunk = "" }
                    for character in word {
                        if height(chunk + String(character), w, size: size) > maxHeight, !chunk.isEmpty {
                            result.append(chunk); chunk = ""
                        }
                        chunk.append(character)
                    }
                }
            }
            if !chunk.isEmpty { result.append(chunk) }
            return result.isEmpty ? [""] : result
        }

        beginPage()
        let metadataTop: CGFloat
        if manolo {
            // Draw the complete supplied artwork from the paper's top edge, behind the content.
            if let background = ManoloInvoiceBrand.image("background.png") {
                picture(ManoloInvoiceBrand.data("background.png"), NSRect(x: (pageWidth - 334) / 2, y: 0,
                    width: 334, height: 334 * background.size.height / background.size.width))
            }
            // 22 CSS pixels correspond to 16.5 PDF points.
            picture(ManoloInvoiceBrand.data("logo.svg"), NSRect(x: (pageWidth - 182.4) / 2, y: 28.5, width: 182.4, height: 36))
            metadataTop = 76.5
        } else {
            let logoTop: CGFloat = compact ? 22 : 32
            let logoSize = MonoInvoiceBrand.image(for: invoice)?.size ?? NSSize(width: 1559, height: 158)
            let logoHeight = width * logoSize.height / logoSize.width
            picture(MonoInvoiceBrand.data(for: invoice), NSRect(x: left, y: logoTop, width: width, height: logoHeight))
            metadataTop = logoTop + logoHeight + (compact ? 14 : 30)
        }
        text(t("Číslo faktúry"), left, metadataTop, 245, size: 7.5, color: muted)
        let numberHeight = text(invoice.number, left, metadataTop + 14, 245, size: 12, weight: .bold)
        text(t("FAKTÚRA"), 310, metadataTop + 16, 253, size: 10, weight: .semibold, alignment: .right)
        y = metadataTop + max(45, 23 + numberHeight)
        rule(y, heavy: true); y += manolo ? 14 : 21
        y = max(company(t("DODÁVATEĽ"), invoice.supplier, x: left, top: y),
                company(t("ODBERATEĽ"), invoice.customer, x: 310, top: y)) + 10
        if !invoice.supplier.registration.isEmpty {
            y += text(invoice.supplier.registration, left, y, width, size: 7, color: muted) + 12
        }
        let bank = [(t("Banka"), invoice.account?.name ?? ""),
                    ("IBAN", invoice.account.map { Format.iban($0.iban) } ?? ""),
                    ("SWIFT", invoice.account?.swift ?? ""),
                    (t("Variabilný symbol"), invoice.variableSymbol),
                    (t("Konštantný symbol"), invoice.constantSymbol),
                    (t("Špecifický symbol"), invoice.specificSymbol)]
        let dates = [(t("Dátum vystavenia"), Format.date(invoice.issueDate)),
                     (t("Dátum splatnosti"), Format.date(invoice.dueDate)),
                     (t("Dátum dodania"), invoice.deliveryDate.map(Format.date) ?? ""),
                     (t("Forma úhrady"), t(invoice.paymentMethod)), (t("Objednávka"), invoice.orderNumber)]
        y = max(detailRows(bank, x: left, top: y), detailRows(dates, x: 310, top: y)) + (manolo && compact ? 9 : 17)
        ensure(75); tableHeader()
        let itemFontSize: CGFloat = 8
        let itemDetailFontSize: CGFloat = 7
        for item in invoice.items {
            let description = [item.name, item.detail, item.discount > 0 ? "\(t("Zľava")) \(Format.number(item.discount)) %" : "",
                               invoice.supplier.vatPayer ? "\(t("DPH")) \(Format.number(item.vatRate)) %" : ""].filter { !$0.isEmpty }.joined(separator: "\n")
            let source = description as NSString
            let detailRange = NSRange(location: item.name.isEmpty ? 0 : (item.name as NSString).length + 1,
                                      length: (item.detail as NSString).length)
            var sourceOffset = 0
            let values = ["\(Format.number(item.quantity)) \(t(item.unit))", Format.money(item.unitPrice, currency: invoice.currency),
                          Format.money(item.total(vatEnabled: invoice.supplier.vatPayer), currency: invoice.currency)]
            for (index, chunk) in chunks(description, w: 246, maxHeight: 270, size: itemFontSize).enumerated() {
                let valueHeight = index == 0 ? zip(values, [CGFloat(62), 92, 101]).map { height($0.0, $0.1, size: itemFontSize) }.max() ?? 0 : 0
                let rowHeight = max(32, max(height(chunk, 246, size: itemFontSize), valueHeight) + (manolo && compact ? 14 : 18))
                if y + rowHeight > bottom { continued(); tableHeader() }
                // Locate each page fragment in order so only the item's detail stays muted,
                // including continuations and descriptions repeating the item's name.
                let fragmentRange = source.range(of: chunk, range: NSRange(location: sourceOffset, length: source.length - sourceOffset))
                let styled = NSMutableAttributedString(attributedString: attributed(chunk, size: itemFontSize))
                if fragmentRange.location != NSNotFound {
                    let secondaryRange = NSRange(location: (item.name as NSString).length, length: source.length - (item.name as NSString).length)
                    let secondary = NSIntersectionRange(fragmentRange, secondaryRange)
                    if secondary.length > 0 {
                        styled.addAttribute(.font, value: InvoiceTypography.font(size: itemDetailFontSize, monospaced: !manolo),
                                            range: NSRange(location: secondary.location - fragmentRange.location, length: secondary.length))
                    }
                    let detail = NSIntersectionRange(fragmentRange, detailRange)
                    if detail.length > 0 {
                        styled.addAttribute(.foregroundColor, value: muted,
                                            range: NSRange(location: detail.location - fragmentRange.location, length: detail.length))
                    }
                    sourceOffset = NSMaxRange(fragmentRange)
                }
                styled.draw(with: NSRect(x: left, y: y + 9, width: 246, height: height(chunk, 246, size: itemFontSize) + 2),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
                if index == 0 {
                    text(values[0], 290, y + 9, 62, size: itemFontSize, alignment: .right)
                    text(values[1], 361, y + 9, 92, size: itemFontSize, alignment: .right)
                    text(values[2], 462, y + 9, 101, size: itemFontSize, alignment: .right)
                }
                y += rowHeight; rule(y)
            }
        }
        y += manolo && compact ? 6 : 8
        var totals: [(String, Decimal, Bool)] = []
        if invoice.supplier.vatPayer {
            totals.append((t("Základ dane"), invoice.net, false))
            for rate in Set(invoice.items.map(\.vatRate)).sorted() {
                totals.append(("\(t("DPH")) \(Format.number(rate)) %", invoice.items.filter { $0.vatRate == rate }.reduce(0) { $0 + $1.vat(enabled: true) }, false))
            }
        }
        totals += [(t("Celková suma"), invoice.total, false), (t("Uhradené"), invoice.paid, false), (t("Suma na úhradu"), invoice.remaining, true)]
        if invoice.overpayment > 0 { totals.append((t("Preplatok"), invoice.overpayment, false)) }
        let note = [invoice.note.isEmpty ? "" : "\(t("Poznámka")): \((invoice.note == "Nie sme platiteľmi DPH." ? t(invoice.note) : invoice.note))", qrError].filter { !$0.isEmpty }.joined(separator: "\n")
        let closingHeight = max(qr == nil ? 0 : PaymentQRImage.blockHeight, invoice.signature == nil ? 0 : 85)
        let noteHeight = height(note, width, size: 8)
        let paymentColumns = ManoloPaymentColumns.make(invoice, width: width - 28, scale: 0.75, monospaced: false, localized: true)
        let paymentHeight = max(48, (paymentColumns.map {
            height($0.value, $0.width, size: $0.valueSize, weight: .semibold)
        }.max() ?? 0) + 28)
        func totalRowHeight(_ amount: Decimal, strong: Bool) -> CGFloat {
            if manolo && strong { return paymentHeight }
            return max(25, height(Format.money(amount, currency: invoice.currency), 193,
                                  size: strong ? 12 : 9, weight: strong ? .bold : .regular) + 12)
        }
        let summaryHeight = totals.reduce(CGFloat.zero) { $0 + totalRowHeight($1.1, strong: $1.2) }
        // Keep a short closing section together instead of exporting a page containing only a QR/signature.
        let closingBlock = summaryHeight + 15 + (note.isEmpty ? 0 : noteHeight + 12) + closingHeight
        ensure(noteHeight < 120 && closingBlock < 650 ? closingBlock : min(summaryHeight, 400))
        for (label, amount, strong) in totals {
            ensure(max(25, height(Format.money(amount, currency: invoice.currency), 193,
                                  size: strong ? 12 : 9, weight: strong ? .bold : .regular) + 12))
            let highlighted = manolo && strong
            let rowHeight = totalRowHeight(amount, strong: strong)
            ensure(rowHeight)
            if highlighted {
                ManoloInvoiceBrand.highlight.setFill()
                NSRect(x: left, y: y, width: width, height: rowHeight).fill()
            }
            if highlighted {
                for (index, column) in paymentColumns.enumerated() {
                    let alignment: NSTextAlignment = index == 3 ? .right : .left
                    text(column.title, left + 14 + column.x, y + 9, column.width,
                         size: 7.5, alignment: alignment)
                    text(column.value, left + 14 + column.x, y + 23, column.width,
                         size: column.valueSize, weight: .semibold, alignment: alignment)
                }
            } else {
                text(label, left, y + 6, 320, size: 9, weight: strong ? .bold : .regular)
                text(Format.money(amount, currency: invoice.currency), 370, y + 6, 193, size: strong ? 12 : 9,
                     weight: strong ? .bold : .regular, alignment: .right)
            }
            y += rowHeight
            if !highlighted { rule(y) }
        }
        y += 15
        for chunk in chunks(note, w: width, maxHeight: 250, size: 8) where !chunk.isEmpty {
            let h = height(chunk, width, size: 8)
            ensure(h + 12)
            y += text(chunk, left, y, width, size: 8, color: muted) + 12
        }
        if closingHeight > 0 {
            ensure(closingHeight)
            if let qr {
                qr.draw(at: NSPoint(x: left, y: y))
                text(qr.payment.label, left, y + PaymentQRImage.side + 2, PaymentQRImage.side,
                     size: 7, weight: .medium, alignment: .center)
            }
            if invoice.signature != nil {
                text(t("Podpis a pečiatka"), 363, y + 5, 200, size: 7, color: muted, alignment: .right)
                picture(invoice.signature, NSRect(x: 393, y: y + 20, width: 170, height: 62))
            }
        }
        endPage(); context.closePDF()
        return pageCount == nil ? render(invoice, template: template, pageCount: page) : output as Data
    }
}
