import AppKit
import SwiftUI
import InvoiceCore
import UniformTypeIdentifiers

@MainActor
final class Store: ObservableObject {
    @Published private(set) var database = Database()
    @Published var error: String?
    @Published var cloudTemplates: [CloudInvoiceStyle]? = nil
    @Published var notice: String?
    @Published private(set) var settingsSaveMessage: String?
    @Published private(set) var invoiceRecovery: [InvoiceRecovery] = []
    @Published private(set) var workspaceRevision = 0
    private var recoveryLoadFailed = false
    private var liveDrafts: [UUID: WeakInvoiceDraft] = [:]
    private(set) var pendingSettings: InvoiceCore.Settings?
    private var settingsSaveTask: Task<Void, Never>?
    private var settingsValidationMessage: String?
    private(set) var loadFailed = false
    let url: URL
    var recoveryURL: URL { url.deletingLastPathComponent().appendingPathComponent("invoice-drafts.json") }
    var pendingRestoreURL: URL { url.deletingLastPathComponent().appendingPathComponent("restore-pending.json") }
    var invoices: [Invoice] {
        let working = Dictionary(uniqueKeysWithValues: invoiceRecovery.map { ($0.id, $0.invoice) })
        return database.invoices.map { working[$0.id] ?? $0 } + invoiceRecovery.filter { draft in
            !database.invoices.contains { $0.id == draft.id }
        }.map(\.invoice)
    }

    init(dataDirectory: URL? = nil, initialDatabase: Database = Database()) {
        let environment = ProcessInfo.processInfo.environment
        let base = dataDirectory ?? (environment["INVOY_DATA_DIR"] ?? environment["FAKTURY_DATA_DIR"]).map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("sk.faktury.desktop")
        url = base.appendingPathComponent("database.json")
        do {
            if FileManager.default.fileExists(atPath: pendingRestoreURL.path) {
                let backup = try DatabaseFile.decode(Data(contentsOf: pendingRestoreURL))
                try finishRestore(backup)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                database = try DatabaseFile.decode(Data(contentsOf: url))
            } else {
                database = initialDatabase
                try DatabaseFile.save(database, to: url)
            }
        } catch {
            loadFailed = true
            self.error = "Dáta sa nepodarilo načítať. Pôvodný súbor zostal zachovaný. Obnovte zálohu v Nastaveniach.\n\(error.localizedDescription)"
        }
        do {
            if FileManager.default.fileExists(atPath: recoveryURL.path) {
                let records = try JSONDecoder().decode([InvoiceRecovery].self, from: Data(contentsOf: recoveryURL))
                guard Set(records.map(\.id)).count == records.count else { throw DataError.invalid("Duplicitné rozpracované faktúry.") }
                invoiceRecovery = records.filter { record in
                    // A crash after committing the invoice but before journal cleanup must not restore stale input.
                    !database.invoices.contains { $0.id == record.id && $0.updatedAt > record.modifiedAt }
                }
            } else { invoiceRecovery = database.invoiceRecovery ?? [] }
        } catch {
            recoveryLoadFailed = true
            self.error = "Rozpracované faktúry sa nepodarilo načítať. Súbor zostal zachovaný.\n\(error.localizedDescription)"
        }
    }

    func register(_ draft: InvoiceDraft) {
        liveDrafts[draft.invoice.id] = WeakInvoiceDraft(draft)
    }

    func unregister(_ draft: InvoiceDraft) {
        if liveDrafts[draft.invoice.id]?.value === draft { liveDrafts[draft.invoice.id] = nil }
    }

    @discardableResult func flushInvoices() -> Bool {
        var success = true
        for draft in liveDrafts.values.compactMap(\.value) { if !draft.flush() { success = false } }
        return success
    }

    @discardableResult func checkpoint(_ record: InvoiceRecovery) -> Bool {
        var records = invoiceRecovery.filter { $0.id != record.id }
        records.append(record)
        return writeRecovery(records)
    }

    @discardableResult private func writeRecovery(_ records: [InvoiceRecovery]) -> Bool {
        guard !loadFailed, !recoveryLoadFailed else { return false }
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: recoveryURL, options: .atomic)
            invoiceRecovery = records
            return true
        } catch { return false }
    }

    @discardableResult func clearRecovery(_ id: UUID) -> Bool {
        guard invoiceRecovery.contains(where: { $0.id == id }) else { return true }
        return writeRecovery(invoiceRecovery.filter { $0.id != id })
    }

    @discardableResult func deleteInvoice(_ id: UUID) -> Bool {
        let prior = invoiceRecovery
        guard clearRecovery(id) else { error = "Rozpracovanú faktúru sa nepodarilo odstrániť."; return false }
        guard update({ $0.invoices.removeAll { $0.id == id } }) else {
            _ = writeRecovery(prior)
            return false
        }
        liveDrafts[id]?.value?.stopAutosave()
        liveDrafts[id] = nil
        return true
    }

    func queueSettingsSave(_ settings: InvoiceCore.Settings, hasInvalidInput: Bool = false) {
        settingsSaveTask?.cancel()
        pendingSettings = settings == database.settings ? nil : settings
        settingsValidationMessage = hasInvalidInput ? "Skontrolujte sadzbu DPH (0 až 100 %)." : settings.validationMessage
        settingsSaveMessage = settingsValidationMessage
        guard pendingSettings != nil, settingsValidationMessage == nil else { return }
        settingsSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flushSettings()
        }
    }

    @discardableResult func flushSettings() -> Bool {
        settingsSaveTask?.cancel()
        settingsSaveTask = nil
        guard settingsValidationMessage == nil else { return false }
        guard let pendingSettings else { return true }
        guard update({ $0.settings = pendingSettings }) else {
            settingsSaveMessage = "Zmeny sa nepodarilo uložiť."
            return false
        }
        self.pendingSettings = nil
        settingsSaveMessage = nil
        return true
    }

    func newInvoice() -> Invoice {
        flushSettings()
        var numbering = database
        numbering.invoices += invoiceRecovery.map(\.invoice)
        var invoice = numbering.newInvoice()
        invoice.cloudStyle = cloudTemplates?.first { $0.id == database.settings.cloudTemplateID } ?? cloudTemplates?.first
        return invoice
    }

    @discardableResult func update(_ change: (inout Database) -> Void) -> Bool {
        guard !loadFailed else { error = "Najprv obnovte dáta zo zálohy v Nastaveniach."; return false }
        var next = database
        change(&next)
        do {
            try next.validateStructure()
            try DatabaseFile.save(next, to: url)
            database = next
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    @discardableResult func applyCloud(_ next: Database) -> Bool {
        guard invoiceRecovery.isEmpty, pendingSettings == nil else { return false }
        guard update({ $0 = next }) else { return false }
        workspaceRevision += 1
        return true
    }

    @discardableResult func save(_ invoice: Invoice) -> Bool {
        if let message = invoice.validation(existing: database.invoices) { error = message; return false }
        var saved = invoice
        saved.number = saved.number.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.updatedAt = Date()
        return update { db in
            if let i = db.invoices.firstIndex(where: { $0.id == saved.id }) { db.invoices[i] = saved }
            else { db.invoices.append(saved) }
        }
    }

    func invoiceTemplateName(_ invoice: Invoice) -> String {
        if let style = invoice.cloudStyle {
            // Names can change in the catalogue; the saved design remains historical.
            return cloudTemplates?.first { $0.id == style.id }?.name ?? style.name
        }
        return invoice.resolvedTemplate(default: database.settings.defaultInvoiceTemplate).title
    }

    func duplicate(_ invoice: Invoice) -> Invoice {
        var copy = invoice
        let fresh = newInvoice()
        copy.id = UUID()
        copy.number = fresh.number
        copy.variableSymbol = fresh.variableSymbol
        copy.issueDate = fresh.issueDate
        copy.dueDate = fresh.dueDate
        copy.deliveryDate = nil
        copy.paid = 0
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.items = copy.items.map { item in var i = item; i.id = UUID(); return i }
        return copy
    }

    func exportBackup() {
        guard flushSettings() else { error = settingsSaveMessage; return }
        guard flushInvoices() else { error = "Niektoré zmeny faktúr sa nepodarilo uložiť."; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "INVOY-zaloha-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do { try DatabaseFile.encode(backupDatabase()).write(to: target, options: .atomic); notice = "Záloha je uložená." }
        catch { self.error = error.localizedDescription }
    }

    func selectBackup() -> Database? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let target = panel.url else { return nil }
        do { return try DatabaseFile.decode(Data(contentsOf: target)) }
        catch { self.error = "Zálohu nemožno obnoviť: \(error.localizedDescription)"; return nil }
    }

    @discardableResult func restore(_ backup: Database) -> Bool {
        settingsSaveTask?.cancel()
        settingsSaveTask = nil
        guard flushInvoices() else { error = "Najprv je potrebné uložiť rozpracované faktúry."; return false }
        do {
            // Keep an independent recovery copy before replacing the active database.
            if FileManager.default.fileExists(atPath: url.path) {
                let snapshot = url.deletingLastPathComponent().appendingPathComponent("pred-obnovou-\(UUID().uuidString).json")
                try DatabaseFile.encode(backupDatabase()).write(to: snapshot, options: .atomic)
            }
            try DatabaseFile.encode(backup).write(to: pendingRestoreURL, options: .atomic)
            for draft in liveDrafts.values.compactMap(\.value) { draft.stopAutosave() }
            liveDrafts.removeAll()
            try finishRestore(backup)
            database = backup
            database.invoiceRecovery = nil
            invoiceRecovery = backup.invoiceRecovery ?? []
            recoveryLoadFailed = false
            workspaceRevision += 1
            pendingSettings = nil
            settingsValidationMessage = nil
            settingsSaveMessage = nil
            loadFailed = false
            notice = "Záloha bola obnovená."
            return true
        } catch {
            if FileManager.default.fileExists(atPath: pendingRestoreURL.path) { loadFailed = true }
            self.error = error.localizedDescription
            return false
        }
    }

    private func finishRestore(_ backup: Database) throws {
        var canonical = backup
        canonical.invoiceRecovery = nil
        try DatabaseFile.save(canonical, to: url)
        try JSONEncoder().encode(backup.invoiceRecovery ?? []).write(to: recoveryURL, options: .atomic)
        try FileManager.default.removeItem(at: pendingRestoreURL)
    }

    func backupDatabase() -> Database {
        var backup = database
        backup.invoiceRecovery = invoiceRecovery.isEmpty ? nil : invoiceRecovery
        return backup
    }

    func exportPDF(_ invoice: Invoice) {
        guard flushInvoices() else { error = "Zmeny faktúr sa nepodarilo uložiť."; return }
        if invoiceRecovery.contains(where: { $0.id == invoice.id }) || invoice.validation(existing: invoices) != nil {
            error = "Pred exportom dokončite údaje faktúry. Rozpracovaná verzia je uložená."
            return
        }
        guard flushSettings() else { error = settingsSaveMessage; return }
        let panel = NSSavePanel()
        let safe = invoice.number.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        panel.title = "Uložiť PDF"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Faktura-\(String(safe)).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do { try InvoicePDF.render(invoice, accentColor: database.settings.invoiceAccent, defaultTemplate: database.settings.defaultInvoiceTemplate).write(to: target, options: .atomic); notice = "PDF je uložené." }
        catch { self.error = error.localizedDescription }
    }

    static func seed() -> Database {
        var db = Database()
        var supplier = Company()
        supplier.name = "Ukážkové štúdio"
        supplier.street = "Ukážková 12"
        supplier.postalCode = "81101"
        supplier.city = "Bratislava"
        supplier.companyID = "12345678"
        supplier.taxID = "1234567890"
        supplier.registration = "Ukážkový zápis v registri"
        supplier.email = "studio@example.test"
        supplier.website = "example.test"
        db.settings.supplier = supplier
        db.settings.issuedBy = supplier.name
        var tatra = BankAccount()
        tatra.name = "Tatra banka, a.s."
        tatra.iban = "SK9611000000002918599669"
        tatra.swift = "TATRSKBX"
        var wise = BankAccount()
        wise.name = "Wise"
        wise.iban = "BE68539007547034"
        wise.swift = "TRWIBEB1XXX"
        db.settings.accounts = [tatra, wise]
        db.settings.defaultAccountID = tatra.id
        // Synthetic verification image, never the owner's real signature.
        let sample = NSImage(size: NSSize(width: 240, height: 60))
        sample.lockFocus()
        ("VZOR" as NSString).draw(at: NSPoint(x: 30, y: 14), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.gray])
        sample.unlockFocus()
        db.settings.signature = sample.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        var customer = Company()
        customer.name = "Ukážkový klient s.r.o."
        customer.street = "Vzorová 15"
        customer.postalCode = "81102"
        customer.city = "Bratislava"
        customer.companyID = "87654321"
        customer.taxID = "0987654321"
        customer.vatID = "SK0987654321"
        customer.vatPayer = true
        db.customers = [customer]
        var invoice = db.newInvoice()
        invoice.number = "2026025"
        invoice.variableSymbol = invoice.number
        let calendar = Calendar.current
        invoice.issueDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))!
        invoice.dueDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
        invoice.customer = customer
        invoice.account = tatra
        invoice.items[0].name = "Grafické práce - návrh propagačných materiálov pre ukážkového klienta"
        invoice.items[0].unitPrice = 800
        invoice.paid = 800
        db.invoices = [invoice]
        return db
    }
}
