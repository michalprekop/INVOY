import SwiftUI
import AppKit
import InvoiceCore

struct Field: View {
    let title: String
    @Binding var text: String
    var numeric = false
    init(_ title: String, text: Binding<String>, numeric: Bool = false) { self.title = title; self._text = text; self.numeric = numeric }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(title, text: $text).labelsHidden().modifier(FormInputStyle())
                .font(.system(size: 13, design: numeric ? .monospaced : .default))
        }
    }
}

struct NumberInput: View {
    let title: String
    @Binding var value: Decimal
    let key: String
    @Binding var invalid: Set<String>
    @State private var input = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(title, text: $input).modifier(FormInputStyle())
                .font(.system(size: 13, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(invalid.contains(key) ? Color.red : .clear))
                .onAppear { input = Format.number(value) }
                .onChange(of: input) { _, new in
                    if let parsed = Format.decimal(new) { value = parsed; invalid.remove(key) }
                    else { invalid.insert(key) }
                }
                .onChange(of: value) { _, new in if Format.decimal(input) != new { input = Format.number(new) } }
                .onDisappear { invalid.remove(key) }
        }
    }
}

struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompanyFields: View {
    @Binding var company: Company
    var supplier = false
    var settingsLayout = false
    var body: some View {
        if settingsLayout {
            VStack(alignment: .leading, spacing: 16) {
                Field("Názov / meno", text: $company.name)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow { Field("Ulica a číslo", text: $company.street); Field("PSČ", text: $company.postalCode, numeric: true) }
                    GridRow { Field("Mesto", text: $company.city); Field("Krajina", text: $company.country) }
                    GridRow { Field("IČO", text: $company.companyID, numeric: true); Field("DIČ", text: $company.taxID, numeric: true) }
                    GridRow { Field("IČ DPH", text: $company.vatID, numeric: true); Field("E-mail", text: $company.email) }
                    GridRow { Field("Telefón", text: $company.phone, numeric: true); Field("Web", text: $company.website) }
                }
                Field("Zápis v registri", text: $company.registration)
                Toggle("Platiteľ DPH", isOn: $company.vatPayer)
            }
        } else {
            VStack(spacing: 13) {
                Field("Názov / meno", text: $company.name)
                Field("Ulica a číslo", text: $company.street)
                HStack { Field("PSČ", text: $company.postalCode, numeric: true).frame(width: 90); Field("Mesto", text: $company.city) }
                Field("Krajina", text: $company.country)
                HStack { Field("IČO", text: $company.companyID, numeric: true); Field("DIČ", text: $company.taxID, numeric: true) }
                Field("IČ DPH", text: $company.vatID, numeric: true)
                HStack { Field("E-mail", text: $company.email); Field("Telefón", text: $company.phone, numeric: true) }
                if supplier {
                    Field("Web", text: $company.website)
                    Field("Zápis v registri", text: $company.registration)
                    Toggle("Platiteľ DPH", isOn: $company.vatPayer)
                }
            }
        }
    }
}

struct InvoiceEditor: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var draft: InvoiceDraft
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var options = false
    private var invoice: Invoice { draft.invoice }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { editorHeading; editorActions }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { editorHeading }
                    HStack(spacing: 8) { Spacer(minLength: 0); editorActions }
                }
            }.padding(.horizontal, 16).padding(.vertical, 13)
            InvoyBrand.line.frame(height: 1).accessibilityHidden(true)
            InvoicePaperCanvas(draft: draft)
            if let message = draft.message {
                Divider()
                HStack {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(draft.saveState == .failed ? .red : .secondary)
                    Spacer()
                    if draft.saveState == .failed {
                        IconButton("Skúsiť uložiť znova", "arrow.clockwise") { _ = draft.flush() }
                    }
                }.padding(12)
            }
        }
    }

    @ViewBuilder private var editorHeading: some View {
        Text.numeric(invoice.number, size: 16, weight: .semibold, monospaced: true)
        StatusBadge(invoice: invoice)
        Text(draft.saveLabel).font(.system(size: 10))
            .foregroundStyle(draft.saveState == .failed ? .red : .secondary)
            .lineLimit(2).frame(maxWidth: 110, alignment: .leading)
        Spacer(minLength: 8)
    }

    @ViewBuilder private var editorActions: some View {
        InvoiceTemplatePicker(draft: draft)
            .frame(width: 200)
            .help("Šablóna faktúry: " + (invoice.cloudStyle?.name ?? invoice.resolvedTemplate(default: store.database.settings.defaultInvoiceTemplate).title))
            .accessibilityLabel("Šablóna faktúry")
        IconButton("Duplikovať", "doc.on.doc", action: onDuplicate)
            .buttonStyle(BrandIconButtonStyle())
        IconButton("Vymazať", "trash", action: onDelete)
            .buttonStyle(BrandIconButtonStyle())
        IconButton("Možnosti faktúry", "slider.horizontal.3") { options.toggle() }
            .buttonStyle(BrandIconButtonStyle())
            .popover(isPresented: $options) {
                invoiceOptions
                    .background(Color(nsColor: .windowBackgroundColor))
                    .presentationBackground(Color(nsColor: .windowBackgroundColor))
            }
        Button { if draft.flush() { store.exportPDF(draft.invoice) } } label: { Label("PDF", systemImage: "square.and.arrow.down") }
            .buttonStyle(BrandButtonStyle()).disabled(!draft.canExport)
            .help("Uložiť PDF")
    }

    private var invoiceOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            InvoiceTemplatePicker(draft: draft)
            Divider()
            if invoice.remaining > 0 {
                Button {
                    draft.invoice.paid = invoice.total
                    options = false
                } label: { Label("Označiť ako uhradenú", systemImage: "checkmark") }
            }
            Toggle("Uviesť dátum dodania", isOn: Binding(get: { invoice.deliveryDate != nil }, set: { draft.invoice.deliveryDate = $0 ? invoice.issueDate : nil }))
            Field("Objednávka", text: $draft.invoice.orderNumber, numeric: true)
            HStack {
                Field("Konštantný symbol", text: $draft.invoice.constantSymbol, numeric: true)
                Field("Špecifický symbol", text: $draft.invoice.specificSymbol, numeric: true)
            }
            Divider()
            if invoice.account != nil {
                Field("Majiteľ účtu", text: Binding(get: { invoice.account?.holderName ?? invoice.supplier.name }, set: { draft.invoice.account?.holderName = $0 }))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Platobný QR kód").font(.system(size: 11)).foregroundStyle(.secondary)
                BrandDropdown(title: "Platobný QR kód", value: (invoice.paymentQRFormat ?? .automatic).title, items: PaymentQRFormat.allCases.map { format in
                    BrandDropdownItem(title: format.title, selected: (invoice.paymentQRFormat ?? .automatic) == format) { draft.invoice.paymentQRFormat = format }
                })
            }
        }.padding(20).frame(width: 360)
    }
}

struct CustomerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var company: Company
    let onSave: (Company) -> Void
    @State private var message: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Odberateľ").font(.system(size: 20, weight: .semibold)); Spacer() }.padding(22)
            Divider()
            ScrollView { CompanyFields(company: $company).padding(22) }
            if let message { Text(message).foregroundStyle(.red).padding(.horizontal, 22) }
            Divider()
            HStack { Spacer(); Button("Zrušiť") { dismiss() }.keyboardShortcut(.cancelAction); Button("Uložiť odberateľa") {
                company.name = company.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if company.name.isEmpty { message = "Doplňte názov odberateľa." } else { onSave(company) }
            }.buttonStyle(BrandButtonStyle()).keyboardShortcut(.defaultAction) }.padding(18)
        }.frame(width: 500, height: 640)
    }
}

struct CustomersView: View {
    @EnvironmentObject private var store: Store
    @State private var search = ""
    @State private var editing: Company?
    @State private var deleting: Company?
    private var customers: [Company] { store.database.customers.filter { search.isEmpty || "\($0.name) \($0.companyID) \($0.city)".localizedStandardContains(search) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Odberatelia").font(.system(size: 26, weight: .semibold)); Text.numeric("\(store.database.customers.count) kontaktov", size: 12).foregroundStyle(.secondary) }
                Spacer()
                BrandSearchField(placeholder: "Hľadať firmu, IČO, mesto", text: $search).frame(width: 230)
                Button { editing = Company() } label: { Label("Nový odberateľ", systemImage: "plus") }.buttonStyle(BrandButtonStyle()).controlSize(.large)
            }.padding(25)
            Divider()
            if customers.isEmpty { ContentUnavailableView("Žiadni odberatelia", systemImage: "building.2").frame(maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(customers) { company in
                            CustomerListRow(company: company, edit: { editing = company }, delete: { deleting = company })
                            Divider()
                        }
                    }.padding(.horizontal, 25)
                }
            }
        }
        .sheet(item: $editing) { company in
            CustomerEditor(company: company) { updated in
                if store.update({ db in
                    if let index = db.customers.firstIndex(where: { $0.id == updated.id }) { db.customers[index] = updated }
                    else { db.customers.append(updated) }
                }) { editing = nil }
            }
        }
        .alert("Vymazať odberateľa?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Zrušiť", role: .cancel) { deleting = nil }
            Button("Vymazať", role: .destructive) { if let id = deleting?.id { _ = store.update { $0.customers.removeAll { $0.id == id } } }; deleting = nil }
        } message: { Text("\(deleting?.name ?? "") bude odstránený z kontaktov. Údaje na existujúcich faktúrach zostanú zachované.") }
    }
}

private struct CustomerListRow: View {
    let company: Company
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: edit) {
                HStack(spacing: 18) {
                    Image(systemName: "building.2").font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 6) {
                        Text.numeric(company.name, weight: .semibold)
                        Text.numeric("\(company.street), \(company.city) · \(company.companyID)", size: 12)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Upraviť odberateľa \(company.name)")
            IconButton("Upraviť odberateľa", "ellipsis", action: edit)
            IconButton("Odstrániť odberateľa", "trash", action: delete)
        }
        .background(hovering ? InvoyBrand.canvas : Color.clear)
        .onHover { hovering = $0 }
    }
}

struct InvoiceTemplatePicker: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var draft: InvoiceDraft
    var body: some View {
        BrandDropdown(title: "Šablóna faktúry", value: draft.invoice.cloudStyle?.name ?? draft.invoice.resolvedTemplate(default: store.database.settings.defaultInvoiceTemplate).title, symbol: "paintpalette", items: options)
    }
    private var options: [BrandDropdownItem] {
        if let templates = store.cloudTemplates {
            var choices = templates
            if let current = draft.invoice.cloudStyle, !choices.contains(where: { $0.id == current.id }) { choices.insert(current, at: 0) }
            return choices.map { style in
                BrandDropdownItem(title: style.name, selected: draft.invoice.cloudStyle?.id == style.id) {
                    draft.invoice.cloudStyle = style; draft.invoice.templateOverride = style.layout
                }
            }
        }
        return [BrandDropdownItem(title: "Podľa globálnych nastavení", selected: draft.invoice.templateOverride == nil) { draft.invoice.templateOverride = nil }] + InvoiceTemplate.allCases.map { template in
            BrandDropdownItem(title: template.title, selected: draft.invoice.templateOverride == template) { draft.invoice.templateOverride = template }
        }
    }
}
