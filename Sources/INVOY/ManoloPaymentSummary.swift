import AppKit
import SwiftUI
import InvoiceCore

/// Size each column to its content and share the remaining space equally.
enum ManoloPaymentColumns {
    struct Column {
        let title: String
        let value: String
        let valueSize: CGFloat
        var width: CGFloat
        var x: CGFloat = 0
    }

    static func make(_ invoice: Invoice, width: CGFloat, scale: CGFloat = 1,
                     monospaced: Bool = false, labelSize: CGFloat = 10,
                     valueSize: CGFloat = 13, localized: Bool = false) -> [Column] {
        let t = (localized ? invoice.documentLanguage : .sk).text
        let values: [(String, String, CGFloat)] = [
            ("IBAN", invoice.account.map { Format.iban($0.iban) } ?? "—", valueSize),
            (t("Variabilný symbol"), invoice.variableSymbol.isEmpty ? "—" : invoice.variableSymbol, valueSize),
            (t("Dátum splatnosti"), Format.date(invoice.dueDate), valueSize),
            (t("Suma na úhradu"), Format.money(invoice.remaining, currency: invoice.currency), 17)
        ]
        var columns = values.map { title, value, size in
            Column(title: title, value: value, valueSize: size * scale, width: ceil(max(
                InvoiceTypography.attributed(title, size: labelSize * scale).size().width,
                InvoiceTypography.attributed(value, size: size * scale, weight: .semibold,
                                             monospaced: monospaced).size().width
            )))
        }
        let naturalWidth = columns.reduce(CGFloat.zero) { $0 + $1.width }
        let compression = min(1, max(1, width - 3 * 16 * scale) / naturalWidth)
        let gap = (width - naturalWidth * compression) / 3
        var x: CGFloat = 0
        for index in columns.indices {
            columns[index].width *= compression
            columns[index].x = x
            x += columns[index].width + gap
        }
        return columns
    }
}

struct ManoloPaymentSummary: View {
    let invoice: Invoice

    var body: some View {
        GeometryReader { proxy in
            let columns = ManoloPaymentColumns.make(invoice, width: proxy.size.width,
                                                     labelSize: 12, valueSize: 15, localized: true)
            ZStack(alignment: .topLeading) {
                ForEach(columns.indices, id: \.self) { index in
                    let column = columns[index]
                    VStack(alignment: index == 3 ? .trailing : .leading, spacing: 7) {
                        Text(column.title).font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        PaperText(column.value, size: column.valueSize, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: column.width, alignment: index == 3 ? .trailing : .leading)
                    .offset(x: column.x)
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color(nsColor: ManoloInvoiceBrand.highlight))
    }
}
