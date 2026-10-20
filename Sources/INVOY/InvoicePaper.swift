import SwiftUI
import AppKit
import InvoiceCore

private struct InvoicePaperLanguageKey: EnvironmentKey {
    static let defaultValue: InvoiceLanguage = .sk
}

extension EnvironmentValues {
    var invoicePaperLanguage: InvoiceLanguage {
        get { self[InvoicePaperLanguageKey.self] }
        set { self[InvoicePaperLanguageKey.self] = newValue }
    }
}

struct InvoicePaperCanvas: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var draft: InvoiceDraft

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, min(1000, proxy.size.width - 48))
            ScrollView([.horizontal, .vertical]) {
                InvoicePaperSurface(draft: draft, width: width)
                    .environment(\.invoiceMonospaced, draft.invoice.resolvedTemplate(default: store.database.settings.defaultInvoiceTemplate) == .mono01)
                    .frame(width: width, alignment: .topLeading)
                    .background { Rectangle().fill(.white).shadow(color: .black.opacity(0.12), radius: 4, y: 1) }
                    .padding(24)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .top)
            }
            .background(InvoyBrand.canvas)
        }
    }
}

/// Lay out at a stable A4 width and zoom uniformly; a narrow window must not reflow the page.
struct InvoicePaperSurface: View {
    @ObservedObject var draft: InvoiceDraft
    let width: CGFloat
    @State private var height: CGFloat = 800 * 297 / 210
    var body: some View {
        InvoicePaper(draft: draft)
            .frame(width: 800).fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                // Read the laid-out height directly, including content below the first A4 page.
                Color.clear.onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, next in height = next }
            })
            .scaleEffect(width / 800, anchor: .topLeading)
            .frame(width: width, height: height * width / 800, alignment: .topLeading)
    }
}

struct InvoicePaper: View {
    @Environment(\.invoiceMonospaced) private var mono
    @EnvironmentObject private var store: Store
    @ObservedObject var draft: InvoiceDraft
    private let pageWidth: CGFloat = 800
    @State private var newCustomer: Company?
    private var manolo: Bool { invoice.resolvedTemplate(default: store.database.settings.defaultInvoiceTemplate) == .manoloBay }
    private var monoLayout: Bool { mono || manolo }
    private var accent: Color { monoLayout ? .black : Color(nsColor: store.database.settings.invoiceAccent.textOnWhite.nsColor) }
    private var invoice: Invoice { draft.invoice }
    private func t(_ value: String) -> String { invoice.documentLanguage.text(value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(monoLayout ? .black : .gray.opacity(0.25)).frame(height: mono ? 10 : manolo ? 2 : 1).padding(.top, manolo ? 12 : 18).padding(.bottom, manolo ? 16 : 24)
            HStack(alignment: .top, spacing: 48) {
                PaperCompany(company: $draft.invoice.supplier, title: "DODÁVATEĽ", accent: accent, supplier: true, compact: manolo)
                PaperCompany(company: $draft.invoice.customer, title: "ODBERATEĽ", accent: accent, compact: manolo)
                    .overlay(alignment: .topTrailing) {
                        BrandDropdown(title: "Vybrať odberateľa", value: "", compact: true, valueFont: .system(size: 13, design: mono ? .monospaced : .default), items:
                            store.database.customers.sorted { $0.name < $1.name }.map { customer in
                                BrandDropdownItem(title: customer.name) { draft.invoice.customer = customer }
                            } + [BrandDropdownItem(title: "Nový odberateľ…", separatorBefore: true) { newCustomer = Company() }]
                        ).frame(width: 24)
                    }
            }
            PaperField("Zápis v registri", text: $draft.invoice.supplier.registration, size: 10, color: .secondary)
                .padding(.top, manolo ? 8 : 16).padding(.bottom, manolo ? 8 : 14)
            rule
            dates.padding(.vertical, manolo ? 12 : 18)
            paymentDetails.padding(.bottom, manolo ? 12 : 20)
            items
            closing.padding(.top, manolo ? 16 : 24)
            if !monoLayout { paymentBand.padding(.top, 20) }
            Spacer(minLength: manolo ? 16 : 50)
            rule
            footer.padding(.top, 14)
        }
        .frame(minHeight: manolo ? pageWidth * 297 / 210 - 78 : nil, alignment: .top)
        .padding(.horizontal, 42).padding(.top, manolo ? 38 : 44).padding(.bottom, 40)
        .frame(minHeight: manolo ? nil : pageWidth * 297 / 210, alignment: .top)
        .background(alignment: .top) {
            if manolo { ManoloInvoiceBackground() }
        }
        .foregroundStyle(Color(red: 0.11, green: 0.15, blue: 0.16))
        .environment(\.invoiceNumericMonospaced, !manolo)
        .environment(\.invoicePaperLanguage, invoice.documentLanguage)
        .environmentObject(draft)
        .sheet(item: $newCustomer) { company in
            CustomerEditor(company: company) { customer in
                if store.update({ $0.customers.append(customer) }) { draft.invoice.customer = customer; newCustomer = nil }
            }
        }
    }

    @ViewBuilder private var rule: some View {
        if mono {
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0.5))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                }.stroke(.black, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }.frame(height: 1)
        } else {
            Rectangle().fill(.gray.opacity(0.25)).frame(height: 1)
        }
    }

    private var footer: some View {
        let contacts = manolo ? Array(ManoloInvoiceBrand.contacts.dropFirst()) :
            [invoice.supplier.website, invoice.supplier.email, invoice.supplier.phone].filter { !$0.isEmpty }
        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Group {
                    if manolo {
                        PaperText("\(t("Vystavil")): Dominika Vašek", size: 10).padding(.vertical, 3)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(t("Vystavil") + ":").font(.system(size: 10, design: mono ? .monospaced : .default))
                                .padding(.vertical, 3).fixedSize()
                            PaperText(invoice.issuedBy.isEmpty ? t("Vystavil") : invoice.issuedBy, size: 10)
                                .padding(.vertical, 3).hidden().accessibilityHidden(true)
                                .overlay {
                                    PaperField("Vystavil", text: $draft.invoice.issuedBy, size: 10, color: .secondary)
                                }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 3) {
                    ForEach(Array(contacts.enumerated()), id: \.offset) { _, contact in
                        PaperText(contact, size: 10).fixedSize(horizontal: false, vertical: true)
                    }
                }.multilineTextAlignment(.center).padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    BrandWordmark(height: 18)
                    Text(verbatim: "www.invoy.xyz").font(.system(size: 7, design: mono ? .monospaced : .default)).fixedSize()
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }.frame(maxWidth: .infinity)
            if !monoLayout, let data = invoice.logo, let logo = NSImage(data: data) {
                Image(nsImage: logo).resizable().scaledToFit()
                    .frame(width: 94 * 0.4, height: 94 * 0.4)
                    .frame(maxWidth: .infinity)
            }
        }.foregroundStyle(.secondary)
    }

    @ViewBuilder private var header: some View {
        if monoLayout {
            VStack(alignment: .leading, spacing: manolo ? 16 : 42) {
                if manolo {
                    ManoloInvoiceHeader()
                } else if let logo = MonoInvoiceBrand.image(for: invoice) {
                    Image(nsImage: logo).resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(invoice.cloudStyle?.config.wordmark ?? "Uncut Corners")
                }
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Číslo faktúry")).font(.system(size: 11, design: mono ? .monospaced : .default)).foregroundStyle(.secondary)
                        PaperField("Číslo faktúry", text: $draft.invoice.number, size: 18, weight: .bold, numeric: true)
                    }
                    Spacer(minLength: 0)
                    Text(t("FAKTÚRA")).font(.system(size: 14, weight: .semibold, design: mono ? .monospaced : .default))
                        .fixedSize().padding(.bottom, 3)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                Text(t("FAKTÚRA")).font(.system(size: 14, weight: .semibold, design: mono ? .monospaced : .default)).foregroundStyle(accent)
                Spacer(minLength: 28)
                PaperField("Číslo faktúry", text: $draft.invoice.number, size: 30, weight: .semibold,
                           numeric: true, alignment: .trailing)
            }.frame(minHeight: 94)
        }
    }

    private var dates: some View {
        HStack(alignment: .top, spacing: 16) {
            paperDate("Dátum vystavenia", date: $draft.invoice.issueDate)
            paperDate("Dátum splatnosti", date: $draft.invoice.dueDate)
            if invoice.deliveryDate != nil {
                paperDate("Dátum dodania", date: Binding(get: { invoice.deliveryDate ?? invoice.issueDate }, set: { draft.invoice.deliveryDate = $0 }))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(t("Forma úhrady")).font(.system(size: 11, design: mono ? .monospaced : .default)).foregroundStyle(.secondary)
                BrandDropdown(title: "Forma úhrady", value: t(draft.invoice.paymentMethod), compact: true, valueFont: .system(size: 13, design: mono ? .monospaced : .default), items: ["Bankový prevod", "Hotovosť", "Platobná karta", "Dobierka"].map { method in
                    BrandDropdownItem(title: t(method), selected: draft.invoice.paymentMethod == method) { draft.invoice.paymentMethod = method }
                }).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paperDate(_ title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(t(title)).font(.system(size: 11, design: mono ? .monospaced : .default)).foregroundStyle(.secondary)
            MonospacedDatePicker(title: title, date: date, fontSize: 13, bordered: false).fixedSize()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paymentDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            BrandDropdown(title: "Bankový účet", value: invoice.account.map { Format.iban($0.iban) + ($0.swift.isEmpty ? "" : "  /  \($0.swift)") } ?? "Vybrať bankový účet", compact: true, valueFont: .system(size: 13, design: mono ? .monospaced : .default), items:
                [BrandDropdownItem(title: "Bez účtu", selected: invoice.account == nil) { draft.invoice.account = nil }] + store.database.settings.accounts.map { account in
                    BrandDropdownItem(title: "\(account.name) · \(Format.iban(account.iban))", selected: invoice.account?.id == account.id) { draft.invoice.account = account }
                }
            ).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                Text(t("Variabilný symbol") + ":").font(.system(size: 12, weight: .medium, design: mono ? .monospaced : .default))
                PaperField("Variabilný symbol", text: $draft.invoice.variableSymbol, size: 12, numeric: true).frame(width: 115)
                if !invoice.constantSymbol.isEmpty {
                    Text(t("KS:")).font(.system(size: 12, design: mono ? .monospaced : .default))
                    PaperField("Konštantný symbol", text: $draft.invoice.constantSymbol, size: 12, numeric: true).frame(width: 68)
                }
                if !invoice.specificSymbol.isEmpty {
                    Text(t("ŠS:")).font(.system(size: 12, design: mono ? .monospaced : .default))
                    PaperField("Špecifický symbol", text: $draft.invoice.specificSymbol, size: 12, numeric: true)
                }
                Spacer(minLength: 0)
            }
            if !invoice.orderNumber.isEmpty {
                HStack(spacing: 12) {
                    Text(t("Objednávka") + ":").font(.system(size: 12, design: mono ? .monospaced : .default))
                    PaperField("Objednávka", text: $draft.invoice.orderNumber, size: 12, numeric: true)
                }
            }
        }
    }

    private var items: some View {
        VStack(spacing: 0) {
            if monoLayout { Rectangle().fill(.black).frame(height: manolo ? 2 : 10) }
            HStack(spacing: 10) {
                Text(t("POLOŽKA")).frame(maxWidth: .infinity, alignment: .leading)
                Text(t("POČET")).frame(width: 52, alignment: .trailing)
                Text(t("JEDNOTKA")).frame(width: 56, alignment: .trailing)
                Text(t("CENA / MJ")).frame(width: 90, alignment: .trailing)
                Text(t(invoice.supplier.vatPayer ? "SPOLU S DPH" : "SPOLU")).frame(width: 110, alignment: .trailing)
            }.font(.system(size: 10, weight: .semibold, design: mono ? .monospaced : .default)).foregroundStyle(.secondary).padding(12).background(Color(white: monoLayout ? 1 : 0.96))
            ForEach($draft.invoice.items) { $item in
                PaperItem(item: $item, currency: invoice.currency, vatPayer: invoice.supplier.vatPayer,
                          canRemove: invoice.items.count > 1, remove: { draft.removeItem(item.id) })
                rule
            }
            HStack {
                Button {
                    var item = InvoiceItem(); item.vatRate = store.database.settings.defaultVAT
                    draft.invoice.items.append(item)
                } label: { Label("Pridať položku", systemImage: "plus").font(.system(size: 13, design: mono ? .monospaced : .default)) }
                .buttonStyle(.plain).foregroundStyle(accent).padding(.vertical, 12)
                Spacer()
                BrandDropdown(title: "Mena", value: draft.invoice.currency, compact: true, valueFont: .system(size: 13, design: mono ? .monospaced : .default), items: ["EUR", "CZK", "USD", "GBP"].map { currency in
                    BrandDropdownItem(title: currency, selected: draft.invoice.currency == currency) { draft.invoice.currency = currency }
                }).frame(width: 72)
            }
        }
    }

    @ViewBuilder private var closing: some View {
        if monoLayout {
            totals
            PaperField("Poznámka", text: $draft.invoice.note, size: 12, color: .secondary, displayValue: invoice.note == "Nie sme platiteľmi DPH." ? t(invoice.note) : invoice.note).padding(.top, manolo ? 12 : 18)
        } else {
            HStack(alignment: .top, spacing: 36) {
                PaperField("Poznámka", text: $draft.invoice.note, size: 12, color: .secondary, displayValue: invoice.note == "Nie sme platiteľmi DPH." ? t(invoice.note) : invoice.note)
                    .frame(maxWidth: .infinity, alignment: .leading)
                totals.frame(width: 320)
            }
        }
    }

    private var totals: some View {
        VStack(spacing: manolo ? 8 : monoLayout ? 12 : 14) {
            if invoice.supplier.vatPayer {
                totalLine("Základ dane", invoice.net)
                ForEach(Array(Set(invoice.items.map(\.vatRate))).sorted(), id: \.self) { rate in
                    totalLine("\(t("DPH")) \(Format.number(rate)) %", invoice.items.filter { $0.vatRate == rate }.reduce(Decimal.zero) { $0 + $1.vat(enabled: true) })
                }
            }
            totalLine("Celková suma", invoice.total, strong: true)
            HStack {
                Text(t("Uhradené")).font(.system(size: 13, design: mono ? .monospaced : .default))
                Spacer()
                PaperNumber(title: "Uhradené", value: $draft.invoice.paid, key: "paid").frame(width: 120)
                Text(invoice.currency).font(.system(size: 12, design: mono ? .monospaced : .default)).foregroundStyle(.secondary)
            }
            if manolo {
                ManoloPaymentSummary(invoice: invoice)
            } else {
                totalLine("Suma na úhradu", invoice.remaining, strong: true, color: accent)
            }
            if invoice.overpayment > 0 { totalLine("Preplatok", invoice.overpayment) }
            if let data = invoice.signature, let signature = NSImage(data: data) {
                VStack(alignment: .trailing, spacing: 7) {
                    Text(t("Podpis a pečiatka")).font(.system(size: 10, design: mono ? .monospaced : .default)).foregroundStyle(.secondary)
                    Image(nsImage: signature).resizable().scaledToFit().frame(width: 238, height: 87)
                }.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 8)
            }
        }
    }

    private func totalLine(_ title: String, _ value: Decimal, strong: Bool = false, color: Color = .primary, highlighted: Bool = false) -> some View {
        HStack {
            PaperText(t(title), size: strong ? 14 : 13, weight: strong ? .semibold : .regular)
            Spacer(minLength: 4)
            PaperText(Format.money(value, currency: invoice.currency), size: strong ? 17 : 13, weight: strong ? .semibold : .regular, monospaced: true)
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }.padding(.horizontal, highlighted ? 18 : 0)
            .padding(.vertical, highlighted ? 22 : 0)
            .padding(.bottom, monoLayout && !highlighted ? 10 : 0)
            .background(highlighted ? Color(nsColor: ManoloInvoiceBrand.highlight) : .clear)
            .overlay(alignment: .bottom) { if monoLayout && !highlighted { rule } }
    }

    private var paymentBand: some View {
        let color = store.database.settings.invoiceAccent
        return GeometryReader { proxy in
            let columns = InvoicePaymentBand.columns(for: invoice, width: proxy.size.width, inset: 16,
                                                     labelSize: 10, valueSize: 13, localized: true)
            ZStack(alignment: .topLeading) {
                ForEach(InvoicePaymentBand.dividerPositions(columns), id: \.self) { x in
                    Rectangle().fill(.white).frame(width: 1, height: proxy.size.height).offset(x: x - 0.5)
                }
                ForEach(columns.indices, id: \.self) { index in
                    let column = columns[index]
                    bandValue(column.title, column.value, monospaced: column.monospaced)
                        .frame(width: column.width, height: proxy.size.height, alignment: .leading)
                        .offset(x: column.x)
                }
            }
        }.frame(height: 82)
            .foregroundStyle(color.usesDarkBandText ? .black : .white).background(Color(nsColor: color.nsColor))
    }

    private func bandValue(_ title: String, _ value: String, monospaced: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(t(title)).font(.system(size: 10, design: mono ? .monospaced : .default)).lineLimit(1).minimumScaleFactor(0.5)
            PaperText(value, size: 13, weight: .semibold, monospaced: monospaced)
                .lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PaperCompany: View {
    @Environment(\.invoicePaperLanguage) private var language
    private func t(_ value: String) -> String { language.text(value) }
    @Environment(\.invoiceMonospaced) private var mono
    @Binding var company: Company
    let title: String?
    let accent: Color
    var supplier = false
    var compact = false
    @State private var details = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(spacing: 6) {
                if let title {
                    Text(t(title)).font(.system(size: 11, weight: .semibold, design: mono ? .monospaced : .default))
                        .foregroundStyle(accent)
                }
                Button { details.toggle() } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, design: mono ? .monospaced : .default))
                        .frame(width: 24, height: 17)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .instantTooltip(supplier ? "Nastavenia dodávateľa" : "Nastavenia odberateľa")
                .accessibilityLabel(supplier ? "Nastavenia dodávateľa" : "Nastavenia odberateľa")
                .popover(isPresented: $details) { CompanyFields(company: $company, supplier: supplier).padding(20).frame(width: 320) }
            }.frame(height: 17)
            PaperField("Názov / meno", text: $company.name, size: 18, weight: .semibold)
            VStack(spacing: 3) {
                PaperField("Ulica a číslo", text: $company.street)
                HStack(alignment: .top, spacing: 6) {
                    PaperField("PSČ", text: $company.postalCode).frame(width: 52)
                    PaperField("Mesto", text: $company.city)
                }
                PaperField("Krajina", text: $company.country)
            }
            VStack(spacing: 3) {
                identifier("IČO", text: $company.companyID)
                identifier("DIČ", text: $company.taxID)
                if !company.vatID.isEmpty { identifier("IČ DPH", text: $company.vatID) }
            }.padding(.top, 4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func identifier(_ title: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(t(title) + ":").font(.system(size: 12, design: mono ? .monospaced : .default)).foregroundStyle(.secondary)
            PaperField(title, text: text, size: 12, numeric: true, color: .secondary, placeholder: "—")
        }
    }
}

private struct PaperItem: View {
    @Environment(\.invoicePaperLanguage) private var language
    private func t(_ value: String) -> String { language.text(value) }
    @Environment(\.invoiceMonospaced) private var mono
    @EnvironmentObject private var draft: InvoiceDraft
    @Binding var item: InvoiceItem
    let currency: String
    let vatPayer: Bool
    let canRemove: Bool
    let remove: () -> Void
    @State private var showDetail = false
    @State private var showDiscount = false
    private var hasDetail: Bool { showDetail || !item.detail.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    PaperField("Názov položky", text: $item.name, size: 11)
                    if hasDetail {
                        PaperField("Podrobný popis", text: $item.detail, size: 11, color: .secondary)
                    }
                }.frame(maxWidth: .infinity)
                number("Množstvo", $item.quantity, "q").frame(width: 52)
                PaperField("Jednotka", text: $item.unit, size: 11, alignment: .trailing, displayValue: t(item.unit)).frame(width: 56)
                number("Cena / MJ", $item.unitPrice, "p").frame(width: 90)
                PaperText(Format.money(item.total(vatEnabled: vatPayer), currency: currency), size: 11, weight: .regular, monospaced: mono)
                    .lineLimit(1).minimumScaleFactor(0.6).frame(width: 110, alignment: .trailing).padding(.top, 3)
            }
            if showDiscount || item.discount > 0 || vatPayer || draft.numericInputs["d" + item.id.uuidString] != nil {
                HStack(spacing: 8) {
                    if showDiscount || item.discount > 0 || draft.numericInputs["d" + item.id.uuidString] != nil {
                        Text(t("Zľava") + " %").font(.system(size: 11, design: mono ? .monospaced : .default)).foregroundStyle(.secondary)
                        number("Zľava %", $item.discount, "d").frame(width: 60)
                    }
                    if vatPayer {
                        Text(t("DPH") + " %").font(.system(size: 11, design: mono ? .monospaced : .default)).foregroundStyle(.secondary)
                        number("DPH %", $item.vatRate, "v").frame(width: 60)
                    }
                    Spacer()
                }
            }
        }.padding(12)
            .environment(\.invoiceNumericMonospaced, mono)
            .contentShape(Rectangle())
            .contextMenu {
                Button(hasDetail ? "Odobrať podrobný popis" : "Pridať podrobný popis") {
                    if hasDetail {
                        item.detail = ""
                        showDetail = false
                    } else {
                        showDetail = true
                    }
                }
                Button("Zľava") { showDiscount = true }
                Divider()
                Button("Odstrániť položku", role: .destructive, action: remove).disabled(!canRemove)
            }
    }

    private func number(_ title: String, _ binding: Binding<Decimal>, _ prefix: String) -> some View {
        PaperNumber(title: title, value: binding, key: prefix + item.id.uuidString, size: 11)
    }
}

struct PaperField: View {
    @Environment(\.invoicePaperLanguage) private var language
    private func t(_ value: String) -> String { language.text(value) }
    @Environment(\.invoiceMonospaced) private var mono
    @Environment(\.invoiceNumericMonospaced) private var numericMono
    let title: String
    @Binding var text: String
    var size: CGFloat = 13
    var weight: NSFont.Weight = .regular
    var numeric = false
    var color: Color = .primary
    var alignment: TextAlignment = .leading
    var outlined = false
    var placeholder: String?
    var displayValue: String?
    @State private var hovering = false
    @FocusState private var focused: Bool

    init(_ title: String, text: Binding<String>, size: CGFloat = 13, weight: NSFont.Weight = .regular,
         numeric: Bool = false, color: Color = .primary, alignment: TextAlignment = .leading, outlined: Bool = false,
         placeholder: String? = nil, displayValue: String? = nil) {
        self.title = title; self._text = text; self.size = size; self.weight = weight
        self.numeric = numeric; self.color = color; self.alignment = alignment
        self.outlined = outlined
        self.placeholder = placeholder
        self.displayValue = displayValue
    }

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .textFieldStyle(.plain).font(Font(InvoiceTypography.font(size: size, weight: weight, monospaced: mono || (numeric && numericMono))))
            .lineLimit(1...)
            .multilineTextAlignment(alignment).focused($focused)
            .foregroundStyle(focused ? color : .clear)
            .overlay(alignment: alignment == .trailing ? .topTrailing : .topLeading) {
                if !focused {
                    PaperText(text.isEmpty ? (placeholder ?? t(title)) : (displayValue ?? text), size: size, weight: weight, monospaced: numeric)
                        .foregroundStyle(text.isEmpty ? .secondary : color).multilineTextAlignment(alignment)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .padding(.vertical, outlined ? 6 : 3).padding(.horizontal, outlined ? 6 : 0)
            .background(focused ? Color.accent.opacity(0.04) : .clear)
            .overlay {
                if outlined { RoundedRectangle(cornerRadius: 3).stroke(focused ? Color.accent : .gray.opacity(hovering ? 0.5 : 0.25), lineWidth: 1) }
            }
            .overlay(alignment: .bottom) {
                if !outlined { Rectangle().fill(Color.accent.opacity(focused ? 0.7 : hovering || (text.isEmpty && placeholder == nil) ? 0.25 : 0)).frame(height: 1) }
            }
            .onHover { hovering = $0 }.help(t(title)).accessibilityLabel(t(title))
            .background(DismissEditingOnOutsideClick(isEditing: focused) { focused = false })
    }
}

private struct PaperNumber: View {
    @EnvironmentObject private var draft: InvoiceDraft
    let title: String
    @Binding var value: Decimal
    let key: String
    var size: CGFloat = 13
    var outlined = false
    private var input: Binding<String> {
        Binding(get: { draft.numericInputs[key] ?? Format.number(value) },
                set: { draft.setNumber($0, key: key, value: $value) })
    }
    var body: some View {
        PaperField(title, text: input, size: size, numeric: true, alignment: .trailing, outlined: outlined)
            .overlay(alignment: .bottom) { if draft.invalid.contains(key) { Color.red.frame(height: 1) } }
    }
}
