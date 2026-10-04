import SwiftUI
import AppKit
import InvoiceCore

@main
struct InvoyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-database"), CommandLine.arguments.count > index + 2 {
            Verification.renderDatabase(path: CommandLine.arguments[index + 1], directory: CommandLine.arguments[index + 2], expectSinglePage: CommandLine.arguments.contains("--expect-single-page"))
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify"), CommandLine.arguments.count > index + 1 {
            Verification.run(directory: CommandLine.arguments[index + 1])
            exit(0)
        }
    }

    var body: some Scene {
        Window("INVOY", id: "main") {
            ProductRootView().environmentObject(store)
                .background(Color(nsColor: .windowBackgroundColor))
                .tint(Color.accent)
                .environment(\.colorScheme, .light)
                .environment(\.locale, Locale(identifier: "sk_SK"))
                .frame(minWidth: 1060, minHeight: 700)
                .alert("Nepodarilo sa uložiť", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
        .defaultSize(width: AppDelegate.launchWidth, height: 930)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nová faktúra") { NotificationCenter.default.post(name: .newInvoice, object: nil) }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Nastavenia…") { NotificationCenter.default.post(name: .showSettings, object: nil) }.keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    var flushInvoiceChanges: (() -> Bool)?
    var confirmCloudTermination: ((@escaping (Bool) -> Void) -> Void)?
    static let launchWidth: CGFloat = 1185
    private var didConfigureMainWindow = false
    override init() { super.init(); Self.shared = self }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard flushInvoiceChanges?() != false else {
            let alert = NSAlert()
            alert.messageText = "Zmeny faktúr sa nepodarilo uložiť"
            alert.informativeText = "Aplikácia zostane otvorená. Skontrolujte dostupnosť disku a skúste uloženie znova."
            alert.addButton(withTitle: "Späť do aplikácie")
            alert.runModal()
            return .terminateCancel
        }
        if let confirmCloudTermination {
            confirmCloudTermination { allowed in NSApp.reply(toApplicationShouldTerminate: allowed) }
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(mainWindowBecameKey), name: NSWindow.didBecomeKeyNotification, object: nil)
        NSApp.setActivationPolicy(.regular)
        // Refresh the running Dock tile after upgrades from the original app icon.
        if let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let iconURL = Bundle.main.url(forResource: iconName, withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { self.configureMainWindow() }
    }
    @objc private func mainWindowBecameKey(_ notification: Notification) {
        DispatchQueue.main.async { self.configureMainWindow() }
    }
    private func configureMainWindow() {
        guard !didConfigureMainWindow, let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) else { return }
        didConfigureMainWindow = true
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        // Keep native title-bar controls readable on black while the workspace stays light.
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.contentView?.appearance = NSAppearance(named: .aqua)
        // Apply after restoration so a previously saved width does not override the launch size.
        var frame = window.frame
        frame.size.width = Self.launchWidth
        if let visible = window.screen?.visibleFrame {
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        }
        window.setFrame(frame, display: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Notification.Name {
    static let newInvoice = Notification.Name("INVOY.newInvoice")
    static let showSettings = Notification.Name("INVOY.showSettings")
}

extension Color {
    static let accent = InvoyBrand.ink
    static let canvas = InvoyBrand.canvas
}

enum SectionID: String, CaseIterable, Identifiable {
    case invoices = "Faktúry", customers = "Odberatelia", settings = "Nastavenia"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .invoices: return "doc.text"; case .customers: return "building.2"; case .settings: return "gearshape" }
    }
}

struct RootView: View {
    @ObservedObject var cloud: NativeCloudSync
    @EnvironmentObject private var store: Store
    @State private var selection: SectionID = .invoices
    @State private var selectedInvoice: UUID?
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    BrandWordmark(height: 30)
                    Spacer()
                    BrandDropdown(title: "Menu účtu", value: accountName, items: [
                        BrandDropdownItem(title: "Nastavenia", symbol: "gearshape") { selection = .settings },
                        BrandDropdownItem(title: "Mac appka", symbol: "desktopcomputer") { NSWorkspace.shared.open(CloudEndpoint.origin.appendingPathComponent("download/mac")) },
                        BrandDropdownItem(title: "Odhlásiť sa", symbol: "rectangle.portrait.and.arrow.right", separatorBefore: true) { Task { await cloud.signOut() } }
                    ]).frame(width: 220).help(cloud.failure ?? accountName)
                }
                HStack(spacing: 2) {
                    ForEach([SectionID.invoices, .customers]) { section in
                        BrandSegment(title: section.rawValue, symbol: section.symbol, iconOnly: false,
                                     selected: selection == section) { selection = section }
                    }
                    if cloud.user?.role == "admin" {
                        BrandSegment(title: "Administrácia", symbol: "checkmark.shield", iconOnly: false, selected: false) {
                            guard store.flushSettings(), store.flushInvoices() else { return }
                            NSWorkspace.shared.open(CloudEndpoint.origin.appendingPathComponent("admin42"))
                        }
                    }
                }.padding(3).background(InvoyBrand.canvas, in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: cloud.user?.role == "admin" ? 420 : 280).accessibilityIdentifier("main-navigation")
            }.padding(.horizontal, 24).padding(.vertical, 14).background(InvoyBrand.surface)
            Divider()
            ZStack {
                // Keep the invoice workspace mounted so navigation preserves drafts and list filters.
                InvoicesView(selectedID: $selectedInvoice)
                    .opacity(selection == .invoices ? 1 : 0)
                    .allowsHitTesting(selection == .invoices)
                    .disabled(selection != .invoices)
                    .accessibilityHidden(selection != .invoices)
                if selection == .customers { CustomersView() }
                if selection == .settings { SettingsView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if let notice = store.notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(20)
                        .task(id: notice) {
                            try? await Task.sleep(for: .seconds(3))
                            if store.notice == notice { store.notice = nil }
                        }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newInvoice)) { _ in
            selection = .invoices
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in selection = .settings }
        .onAppear { AppDelegate.shared?.flushInvoiceChanges = { store.flushInvoices() } }
        .onChange(of: selection) { old, _ in
            if !store.flushInvoices() { selection = old }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            store.flushInvoices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.flushSettings(); store.flushInvoices()
        }
    }
    private var accountName: String {
        let name = cloud.user?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? cloud.user?.email ?? "Môj účet" : name
    }
}

struct InvoicesView: View {
    @EnvironmentObject private var store: Store
    @Binding var selectedID: UUID?
    @State private var draft: InvoiceDraft?
    @State private var search = ""
    @State private var filter = "Všetky"
    @State private var year = 0
    @State private var sortOrder = "Najnovšie"
    @AppStorage("invoiceTableMode") private var tableMode = false
    @State private var deleting: Invoice?
    @State private var exporting = false

    private var filtered: [Invoice] {
        store.invoices.filter {
            $0.matchesSearch(search) &&
            (year == 0 || Calendar.current.component(.year, from: $0.issueDate) == year) &&
            (filter == "Všetky" || (filter == "Uhradené" && $0.remaining == 0) || (filter == "Neuhradené" && $0.remaining > 0) || (filter == "Po splatnosti" && $0.status == "Po splatnosti"))
        }.sorted {
            if sortOrder == "Splatnosť", $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
            if sortOrder == "Odberateľ", $0.customer.name != $1.customer.name { return $0.customer.name < $1.customer.name }
            return $0.issueDate == $1.issueDate ? $0.number > $1.number : $0.issueDate > $1.issueDate
        }
    }
    private var selected: Invoice? { store.invoices.first { $0.id == selectedID } }
    private var listSelection: Binding<UUID?> {
        Binding(get: { draft?.invoice.id ?? selectedID }, set: { id in
            guard let id, id != draft?.invoice.id,
                  let invoice = store.invoices.first(where: { $0.id == id }) else { return }
            request { open(invoice) }
        })
    }
    private var mode: Binding<Bool> {
        Binding(get: { tableMode }, set: { value in request { tableMode = value } })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 2) {
                    ForEach(["Všetky", "Uhradené", "Neuhradené", "Po splatnosti"], id: \.self) { value in
                        BrandSegment(title: value, selected: filter == value) { filter = value }
                    }
                }.padding(3).background(InvoyBrand.canvas, in: RoundedRectangle(cornerRadius: 9))
                    .frame(minWidth: 340, idealWidth: 475, maxWidth: 475)
                VStack(alignment: .leading, spacing: 4) {
                    Text.numeric(Format.invoiceCount(store.invoices.count), size: 17, weight: .semibold)
                    Button { request { exporting = true } } label: {
                        Text("Exportovať").underline().font(.system(size: 12)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).disabled(store.invoices.isEmpty)
                }.fixedSize()
                HStack(spacing: 14) {
                    Spacer(minLength: 0)
                    BrandSearchField(placeholder: "Hľadať vo faktúrach", text: $search)
                        .frame(minWidth: 160, idealWidth: 205, maxWidth: 205)
                    Button { createInvoice() } label: { Label("Nová faktúra", systemImage: "plus") }
                        .buttonStyle(BrandButtonStyle()).controlSize(.large).fixedSize()
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity)
                HStack(spacing: 2) {
                    BrandSegment(title: "Zoznam s náhľadom", symbol: "rectangle.split.2x1", selected: !tableMode) { mode.wrappedValue = false }
                    BrandSegment(title: "Tabuľkový zoznam", symbol: "tablecells", selected: tableMode) { mode.wrappedValue = true }
                }.padding(3).background(InvoyBrand.canvas, in: RoundedRectangle(cornerRadius: 9)).frame(width: 86)
            }.padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            if tableMode {
                invoiceTable
            } else {
                HSplitView {
                    invoiceList.frame(minWidth: 296, idealWidth: 325, maxWidth: 325)
                    if let draft {
                        InvoiceEditor(draft: draft, onDuplicate: { duplicateInvoice(draft.invoice) },
                                      onDelete: { request { deleting = draft.invoice } })
                            .id(draft.invoice.id).frame(minWidth: 640, maxWidth: .infinity)
                    } else {
                        ContentUnavailableView("Vyberte faktúru", systemImage: "doc.richtext").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .onAppear {
            if !store.invoiceRecovery.isEmpty { tableMode = false }
            if draft == nil, let invoice = store.invoiceRecovery.max(by: { $0.modifiedAt < $1.modifiedAt })?.invoice ?? selected ?? filtered.first {
                open(invoice)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newInvoice)) { _ in createInvoice() }
        .sheet(isPresented: $exporting) { InvoiceExportSheet(initialYear: year).environmentObject(store) }
        .onChange(of: search) { _, _ in selectFilteredInvoice() }
        .onChange(of: filter) { _, _ in selectFilteredInvoice() }
        .onChange(of: year) { _, _ in selectFilteredInvoice() }
        .onChange(of: store.workspaceRevision) { _, _ in
            draft = nil
            if let invoice = store.invoiceRecovery.max(by: { $0.modifiedAt < $1.modifiedAt })?.invoice ?? store.invoices.first(where: { $0.id == selectedID }) ?? filtered.first { open(invoice) }
            else { selectedID = nil }
        }
        .alert("Vymazať faktúru \(deleting?.number ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Zrušiť", role: .cancel) { deleting = nil }
            Button("Vymazať", role: .destructive) {
                if let id = deleting?.id, store.deleteInvoice(id), draft?.invoice.id == id {
                    draft = nil; selectedID = nil
                    if let first = filtered.first { open(first) }
                }
                deleting = nil
            }
        } message: { Text("Faktúra bude odstránená zo zoznamu aj z lokálnych dát.") }
    }

    private var invoiceList: some View {
        VStack(spacing: 0) {
            HStack {
                yearPicker
                Spacer(minLength: 8); sortPicker
            }.padding(12)
            Divider()
            List(selection: listSelection) {
                ForEach(filtered) { invoice in
                    InvoiceRow(invoice: invoice, recovering: store.invoiceRecovery.contains { $0.id == invoice.id },
                               isSelected: listSelection.wrappedValue == invoice.id)
                        .tag(invoice.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .listRowBackground(RoundedRectangle(cornerRadius: 8)
                            .fill(listSelection.wrappedValue == invoice.id ? InvoyBrand.canvas : Color.clear)
                            .padding(.horizontal, 10))
                        .contextMenu {
                            Button("Upraviť") { begin(invoice) }
                            Button("Duplikovať") { duplicateInvoice(invoice) }
                            Button("Exportovať PDF") { store.exportPDF(invoice) }
                            Divider()
                            Button("Vymazať", role: .destructive) { request { deleting = invoice } }
                        }
                }
            }.listStyle(.inset).scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, InvoiceRow.height)
                .overlay { if filtered.isEmpty { ContentUnavailableView("Bez výsledkov", systemImage: "doc.text.magnifyingglass") } }
        }
    }

    private var yearPicker: some View {
        let years = [0] + Array(Set(store.invoices.map { Calendar.current.component(.year, from: $0.issueDate) })).sorted(by: >)
        return BrandDropdown(title: "Rok", value: year == 0 ? "Všetky roky" : String(year), items: years.map { option in
            BrandDropdownItem(title: option == 0 ? "Všetky roky" : String(option), selected: year == option) { year = option }
        }).frame(width: 132)
    }

    private var sortPicker: some View {
        BrandDropdown(title: "Zoradenie", value: sortOrder, items: ["Najnovšie", "Splatnosť", "Odberateľ"].map { option in
            BrandDropdownItem(title: option, selected: sortOrder == option) { sortOrder = option }
        }).frame(width: 132)
    }

    private var invoiceTable: some View {
        VStack(spacing: 0) {
            HStack {
                yearPicker
                Spacer(); sortPicker
                if let invoice = selected {
                    IconButton("Duplikovať", "doc.on.doc") { duplicateInvoice(invoice) }
                    IconButton("Vymazať", "trash") { request { deleting = invoice } }
                    Button { begin(invoice) } label: { Label("Upraviť", systemImage: "pencil") }
                    Button { store.exportPDF(invoice) } label: { Label("PDF", systemImage: "square.and.arrow.down") }
                }
            }.padding(14)
            Table(filtered, selection: listSelection) {
                TableColumn("Číslo") { invoice in
                    Button { begin(invoice) } label: {
                        Text.numeric(invoice.number, weight: .semibold, monospaced: true)
                    }.buttonStyle(.plain).foregroundStyle(Color.accent).padding(.vertical, 14)
                        .background(InvoiceSelectionBackground(selected: listSelection.wrappedValue == invoice.id))
                }.width(min: 80, ideal: 105)
                TableColumn("Odberateľ") { invoice in
                    VStack(alignment: .leading, spacing: 5) {
                        Text.numeric(invoice.customer.name, weight: .medium)
                        Text.numeric(invoice.items.first?.name ?? "", size: 11).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.width(min: 160, ideal: 290)
                TableColumn("Stav") { invoice in
                    StatusBadge(invoice: invoice, isSelected: listSelection.wrappedValue == invoice.id)
                }.width(min: 100, ideal: 130)
                TableColumn("Suma") { invoice in
                    Text.numeric(Format.money(invoice.total, currency: invoice.currency), weight: .medium, monospaced: true)
                        .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 105, ideal: 130)
                TableColumn("Vystavenie / splatnosť") { invoice in
                    VStack(alignment: .trailing, spacing: 5) {
                        Text.numeric(Format.date(invoice.issueDate), size: 11, monospaced: true).foregroundStyle(.secondary)
                        Text.numeric(Format.date(invoice.dueDate), size: 11, monospaced: true)
                            .foregroundStyle(invoice.status == "Po splatnosti" ? .red : .primary)
                    }.frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 135, ideal: 155)
            }.foregroundStyle(InvoyBrand.ink)
                .overlay { if filtered.isEmpty { ContentUnavailableView("Žiadne faktúry", systemImage: "doc.text.magnifyingglass") } }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let invoice = store.invoices.first(where: { ids.contains($0.id) }) {
                        Button("Upraviť") { begin(invoice) }
                        Button("Duplikovať") { duplicateInvoice(invoice) }
                        Button("Exportovať PDF") { store.exportPDF(invoice) }
                        Button("Vymazať", role: .destructive) { request { deleting = invoice } }
                    }
                } primaryAction: { ids in
                    if let invoice = store.invoices.first(where: { ids.contains($0.id) }) { begin(invoice) }
                }
        }
    }

    private func request(_ action: @escaping () -> Void) {
        guard draft?.flush() != false else { return }
        action()
    }
    private func open(_ invoice: Invoice) {
        draft?.stopAutosave()
        selectedID = invoice.id
        draft = InvoiceDraft(invoice, isNew: !store.database.invoices.contains { $0.id == invoice.id }, store: store)
    }
    private func begin(_ invoice: Invoice) {
        request { open(invoice); tableMode = false }
    }
    private func createInvoice() {
        request { search = ""; filter = "Všetky"; year = 0; open(store.newInvoice()); tableMode = false }
    }
    private func duplicateInvoice(_ invoice: Invoice) {
        // Assign the number after any pending draft has been saved.
        request { search = ""; filter = "Všetky"; year = 0; open(store.duplicate(invoice)); tableMode = false }
    }
    private func selectFilteredInvoice() {
        guard !filtered.contains(where: { $0.id == selectedID }) else { return }
        request {
            if let first = filtered.first { open(first) }
            else { draft?.stopAutosave(); draft = nil; selectedID = nil }
        }
    }
}

struct InvoiceRow: View {
    static let height: CGFloat = 64
    let invoice: Invoice
    var recovering = false
    var isSelected = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text.numeric(invoice.number, weight: .semibold, monospaced: true).lineLimit(1).minimumScaleFactor(0.75)
                StatusBadge(invoice: invoice, isSelected: isSelected).fixedSize()
                Spacer(minLength: 0)
                Text.numeric(Format.date(invoice.issueDate), size: 11, monospaced: true)
                    .foregroundStyle(.secondary).fixedSize().help("Dátum vystavenia")
            }.frame(height: 22)
            HStack(spacing: 6) {
                Text.numeric(invoice.customer.name).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).help(invoice.customer.name)
                Image(systemName: "pencil.circle").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(width: 14, height: 14).opacity(recovering ? 1 : 0)
                    .help("Rozpracované uložené").accessibilityLabel("Rozpracované uložené").accessibilityHidden(!recovering)
                Text.numeric(Format.money(invoice.total, currency: invoice.currency), weight: .semibold, monospaced: true)
                    .lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
            }.frame(height: 16)
        }.padding(.vertical, 10).frame(height: Self.height)
            .foregroundStyle(InvoyBrand.ink)
            .background(InvoiceSelectionBackground(selected: isSelected))
    }
}

struct StatusBadge: View {
    let invoice: Invoice
    var isSelected = false
    var color: Color {
        if invoice.remaining == 0 { return Color(red: 0.16, green: 0.47, blue: 0.40) }
        return invoice.status == "Po splatnosti" ? .red : Color(red: 0.6, green: 0.38, blue: 0.05)
    }
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(invoice.status).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(isSelected ? Color.white : color.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct Metric: View {
    let label: String
    let value: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary); Text.numeric(value, size: 14, weight: .medium, monospaced: true).lineLimit(1).minimumScaleFactor(0.75) } }
}

struct IconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    init(_ title: String, _ symbol: String, action: @escaping () -> Void) { self.title = title; self.symbol = symbol; self.action = action }
    var body: some View { Button(action: action) { Image(systemName: symbol).frame(width: 19, height: 21) }.help(title).accessibilityLabel(title) }
}
