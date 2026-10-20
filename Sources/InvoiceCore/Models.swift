import Foundation

public func rounded(_ value: Decimal, scale: Int = 2) -> Decimal {
    var source = value
    var result = Decimal()
    NSDecimalRound(&result, &source, scale, .plain)
    return result
}

public enum Format {
    public static func invoiceCount(_ count: Int) -> String {
        "\(count) " + (count == 1 ? "faktúra" : (2...4).contains(count) ? "faktúry" : "faktúr")
    }
    public static func money(_ value: Decimal, currency: String = "EUR") -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "sk_SK")
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: value as NSDecimalNumber) ?? "0,00"
    }

    public static func number(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "sk_SK")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.usesGroupingSeparator = false
        return f.string(from: value as NSDecimalNumber) ?? "0"
    }

    public static func date(_ value: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sk_SK")
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: value)
    }

    public static func decimal(_ value: String) -> Decimal? {
        let clean = value.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: ",", with: ".")
        guard clean.range(of: #"^-?\d+(\.\d{0,4})?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func iban(_ value: String) -> String {
        let chars = Array(value.filter { !$0.isWhitespace }.uppercased())
        return stride(from: 0, to: chars.count, by: 4).map { String(chars[$0..<min($0 + 4, chars.count)]) }.joined(separator: " ")
    }
}

public struct Company: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name = ""
    public var street = ""
    public var postalCode = ""
    public var city = ""
    public var country = "Slovensko"
    public var companyID = ""
    public var taxID = ""
    public var vatID = ""
    public var email = ""
    public var phone = ""
    public var website = ""
    public var registration = ""
    public var vatPayer = false
    public init() {}
    public var address: String { [street, "\(postalCode) \(city)".trimmingCharacters(in: .whitespaces), country].filter { !$0.isEmpty }.joined(separator: "\n") }
}

public struct BankAccount: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name = ""
    public var iban = ""
    public var swift = ""
    public var holderName: String? = nil
    public init() {}
    public var isValid: Bool {
        let clean = iban.filter { !$0.isWhitespace }.uppercased()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (15...34).contains(clean.count),
              clean.range(of: #"^[A-Z]{2}[0-9]{2}[A-Z0-9]+$"#, options: .regularExpression) != nil else { return false }
        let rearranged = String(clean.dropFirst(4)) + clean.prefix(4)
        var remainder = 0
        for ch in rearranged.unicodeScalars {
            let value = ch.value >= 65 ? Int(ch.value - 55) : Int(ch.value - 48)
            remainder = (remainder * (value >= 10 ? 100 : 10) + value) % 97
        }
        return remainder == 1
    }
}

public struct InvoiceItem: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name = ""
    public var detail = ""
    public var quantity: Decimal = 1
    public var unit = "ks"
    public var unitPrice: Decimal = 0
    public var discount: Decimal = 0
    public var vatRate: Decimal = 0
    public init() {}
    public var net: Decimal { rounded(quantity * unitPrice * (1 - discount / 100)) }
    public func vat(enabled: Bool) -> Decimal { enabled ? rounded(net * vatRate / 100) : 0 }
    public func total(vatEnabled: Bool) -> Decimal { net + vat(enabled: vatEnabled) }
}

public enum PaymentQRFormat: String, Codable, CaseIterable {
    case automatic, payBySquare, qrPlatba, disabled

    public var title: String {
        switch self {
        case .automatic: return "Automaticky podľa odberateľa"
        case .payBySquare: return "PAY by square (Slovensko)"
        case .qrPlatba: return "QR Platba (Česko)"
        case .disabled: return "Bez QR kódu"
        }
    }
}

public struct Invoice: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var number = ""
    public var variableSymbol = ""
    public var constantSymbol = ""
    public var specificSymbol = ""
    public var orderNumber = ""
    public var issueDate = Date()
    public var dueDate = Date()
    public var deliveryDate: Date? = nil
    public var supplier = Company()
    public var customer = Company()
    public var account: BankAccount? = nil
    public var items: [InvoiceItem] = [InvoiceItem()]
    public var currency = "EUR"
    public var paymentMethod = "Bankový prevod"
    public var language: InvoiceLanguage? = nil
    public var documentLanguage: InvoiceLanguage { language ?? .sk }
    public var paymentQRFormat: PaymentQRFormat? = nil
    public var templateOverride: InvoiceTemplate? = nil
    public var cloudStyle: CloudInvoiceStyle? = nil
    public var note = ""
    public var issuedBy = ""
    public var paid: Decimal = 0
    public var logo: Data? = nil
    public var signature: Data? = nil
    public var createdAt = Date()
    public var updatedAt = Date()
    public init() {}
    public var net: Decimal { items.reduce(0) { $0 + $1.net } }
    public var vat: Decimal { items.reduce(0) { $0 + $1.vat(enabled: supplier.vatPayer) } }
    public var total: Decimal { net + vat }
    public var remaining: Decimal { max(0, rounded(total - paid)) }
    public var overpayment: Decimal { max(0, rounded(paid - total)) }
    public var status: String {
        if remaining == 0 { return "Uhradená" }
        if Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: Date()) { return "Po splatnosti" }
        return paid > 0 ? "Čiastočne uhradená" : "Na úhradu"
    }
    public func matchesSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return true }
        let fields = [number, variableSymbol, orderNumber, customer.name, customer.companyID,
                      customer.taxID, customer.vatID, note] + items.flatMap { [$0.name, $0.detail] }
        return terms.allSatisfy { term in fields.contains { $0.localizedStandardContains(term) } }
    }
    public func validation(existing: [Invoice]) -> String? {
        if number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Doplňte číslo faktúry." }
        if existing.contains(where: { $0.id != id && $0.number.caseInsensitiveCompare(number) == .orderedSame }) { return "Faktúra s týmto číslom už existuje." }
        if supplier.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Doplňte názov dodávateľa." }
        if customer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Vyberte alebo doplňte odberateľa." }
        if items.isEmpty { return "Pridajte aspoň jednu položku." }
        if items.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.quantity <= 0 || $0.unitPrice < 0 || $0.discount < 0 || $0.discount > 100 || $0.vatRate < 0 || $0.vatRate > 100 }) { return "Skontrolujte položky: názov, kladné množstvo, cenu a sadzby od 0 do 100 %." }
        if paid < 0 { return "Uhradená suma nemôže byť záporná." }
        if dueDate < Calendar.current.startOfDay(for: issueDate) { return "Splatnosť nemôže byť pred dátumom vystavenia." }
        if paymentMethod == "Bankový prevod" && account == nil { return "Vyberte bankový účet." }
        if let account, !account.isValid { return "Skontrolujte IBAN bankového účtu." }
        if variableSymbol.count > 10 || (!variableSymbol.isEmpty && variableSymbol.range(of: #"^[0-9]+$"#, options: .regularExpression) == nil) { return "Variabilný symbol môže obsahovať najviac 10 číslic." }
        return nil
    }
}

public struct Settings: Codable, Equatable {
    public var supplier = Company()
    public var accounts: [BankAccount] = []
    public var defaultAccountID: UUID? = nil
    public var dueDays = 14
    public var currency = "EUR"
    public var numberPrefix = ""
    public var numberDigits = 3
    public var defaultNote = "Nie sme platiteľmi DPH."
    public var issuedBy = ""
    public var defaultVAT: Decimal = 0
    public var invoiceAccentHex: String? = nil
    public var invoiceTemplate: InvoiceTemplate? = nil
    public var cloudTemplateID: String? = nil
    public var logo: Data? = nil
    public var signature: Data? = nil
    public init() {}
    public var invoiceAccent: InvoiceAccent { invoiceAccentHex.flatMap(InvoiceAccent.init(hex:)) ?? .standard }
    public var defaultInvoiceTemplate: InvoiceTemplate { invoiceTemplate ?? .boringDefault01 }
    public var validationMessage: String? {
        if supplier.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Doplňte názov svojej firmy." }
        if defaultVAT < 0 || defaultVAT > 100 { return "Skontrolujte sadzbu DPH (0 až 100 %)." }
        if !accounts.allSatisfy(\.isValid) { return "Skontrolujte bankové účty." }
        if let invoiceAccentHex, InvoiceAccent(hex: invoiceAccentHex) == nil { return "Skontrolujte farbu faktúry." }
        return nil
    }
}

public struct InvoiceRecovery: Codable, Equatable, Identifiable {
    public var invoice: Invoice
    public var numericInputs: [String: String]
    public var modifiedAt: Date
    public var id: UUID { invoice.id }
    public init(invoice: Invoice, numericInputs: [String: String] = [:], modifiedAt: Date = Date()) {
        self.invoice = invoice
        self.numericInputs = numericInputs
        self.modifiedAt = modifiedAt
    }
}

public struct Database: Codable, Equatable {
    public var schemaVersion = 1
    public var settings = Settings()
    public var customers: [Company] = []
    public var invoices: [Invoice] = []
    // Backups include unfinished input; live recovery is stored separately from validated invoices.
    public var invoiceRecovery: [InvoiceRecovery]? = nil
    public init() {}

    public func nextNumber(date: Date = Date()) -> String {
        let year = Calendar.current.component(.year, from: date)
        let prefix = settings.numberPrefix + String(year)
        let digits = min(8, max(1, settings.numberDigits))
        let maxSequence = invoices.compactMap { invoice -> Int? in
            guard invoice.number.hasPrefix(prefix) else { return nil }
            let suffix = String(invoice.number.dropFirst(prefix.count))
            guard suffix.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else { return nil }
            return Int(suffix)
        }.max() ?? 0
        return prefix + String(format: "%0*d", digits, maxSequence + 1)
    }

    public func newInvoice() -> Invoice {
        var invoice = Invoice()
        invoice.number = nextNumber()
        invoice.variableSymbol = String(invoice.number.filter(\.isNumber).suffix(10))
        invoice.dueDate = Calendar.current.date(byAdding: .day, value: settings.dueDays, to: invoice.issueDate) ?? invoice.issueDate
        invoice.supplier = settings.supplier
        invoice.currency = settings.currency
        invoice.note = settings.defaultNote
        invoice.issuedBy = settings.issuedBy
        invoice.logo = settings.logo
        invoice.signature = settings.signature
        invoice.items[0].vatRate = settings.defaultVAT
        invoice.account = settings.accounts.first(where: { $0.id == settings.defaultAccountID }) ?? settings.accounts.first
        return invoice
    }

    public func validateStructure() throws {
        guard schemaVersion == 1 else { throw DataError.invalid("Nepodporovaná verzia zálohy.") }
        let recovery = invoiceRecovery ?? []
        guard Set(recovery.map(\.id)).count == recovery.count else { throw DataError.invalid("Záloha obsahuje duplicitné rozpracované faktúry.") }
        guard Set(invoices.map(\.id)).count == invoices.count,
              Set(invoices.map { $0.number.lowercased() }).count == invoices.count,
              Set(customers.map(\.id)).count == customers.count,
              Set(settings.accounts.map(\.id)).count == settings.accounts.count else { throw DataError.invalid("Záloha obsahuje duplicitné záznamy.") }
        guard (0...365).contains(settings.dueDays), (1...8).contains(settings.numberDigits),
              settings.defaultVAT >= 0, settings.defaultVAT <= 100 else { throw DataError.invalid("Neplatné nastavenia v zálohe.") }
        for invoice in invoices {
            if let message = invoice.validation(existing: []) { throw DataError.invalid("\(invoice.number): \(message)") }
        }
    }
}

public enum DataError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum DatabaseFile {
    public static func decode(_ data: Data) throws -> Database {
        let db = try JSONDecoder().decode(Database.self, from: data)
        try db.validateStructure()
        return db
    }
    public static func encode(_ database: Database) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(database)
    }
    public static func save(_ database: Database, to url: URL) throws {
        let data = try encode(database)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            try previous.write(to: url.deletingPathExtension().appendingPathExtension("previous.json"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}
