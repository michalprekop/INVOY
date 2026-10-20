import AppKit
import InvoiceCore

enum InvoicePaymentBand {
    struct Column {
        let title: String
        let value: String
        let monospaced: Bool
        var x: CGFloat = 0
        var width: CGFloat = 0
    }

    static func columns(for invoice: Invoice, width: CGFloat, inset: CGFloat,
                        labelSize: CGFloat, valueSize: CGFloat, localized: Bool = false) -> [Column] {
        let t = (localized ? invoice.documentLanguage : .sk).text
        var columns = [
            Column(title: "IBAN", value: invoice.account.map { Format.iban($0.iban) } ?? t(invoice.paymentMethod),
                   monospaced: invoice.account != nil),
            Column(title: t("Variabilný symbol"), value: invoice.variableSymbol, monospaced: true),
            Column(title: t("Splatnosť"), value: Format.date(invoice.dueDate), monospaced: true),
            Column(title: t("Na úhradu"), value: Format.money(invoice.remaining, currency: invoice.currency), monospaced: true)
        ]
        for index in columns.indices {
            let column = columns[index]
            columns[index].width = ceil(max(
                InvoiceTypography.attributed(column.title, size: labelSize).size().width,
                InvoiceTypography.attributed(column.value, size: valueSize, weight: .semibold,
                                             monospaced: column.monospaced).size().width
            ))
        }
        let naturalWidth = columns.reduce(CGFloat.zero) { $0 + $1.width }
        let minimumGap = inset * 2
        let availableWidth = max(1, width - inset * 2 - minimumGap * CGFloat(columns.count - 1))
        let scale = min(1, availableWidth / naturalWidth)
        let gap = (width - inset * 2 - naturalWidth * scale) / CGFloat(columns.count - 1)
        var x = inset
        for index in columns.indices {
            columns[index].x = x
            columns[index].width *= scale
            x += columns[index].width + gap
        }
        return columns
    }

    static func dividerPositions(_ columns: [Column]) -> [CGFloat] {
        zip(columns, columns.dropFirst()).map { left, right in
            (left.x + left.width + right.x) / 2
        }
    }
}
