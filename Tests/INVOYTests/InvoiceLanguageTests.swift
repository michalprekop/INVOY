import XCTest
import PDFKit
import SwiftUI
import AppKit
import InvoiceCore
@testable import INVOY

final class InvoiceLanguageTests: XCTestCase {
    @MainActor func testLanguagePickerFitsNativeEditor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(dataDirectory: directory, initialDatabase: Store.seed())
        var invoice = store.database.invoices[0]
        invoice.language = .en
        let draft = InvoiceDraft(invoice, store: store)
        let host = NSHostingView(rootView: InvoiceEditor(draft: draft, onDuplicate: {}, onDelete: {})
            .environmentObject(store).frame(width: 1000, height: 900))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 1000, accuracy: 1)
        if let output = ProcessInfo.processInfo.environment["INVOY_LANGUAGE_QA"] {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("native-editor.png"))
        }
    }

    func testLegacyDefaultsAndLanguageRoundTrip() throws {
        let legacy = Invoice()
        let decoded = try JSONDecoder().decode(Invoice.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.documentLanguage, .sk)
        var english = legacy
        english.language = .en
        XCTAssertEqual(try JSONDecoder().decode(Invoice.self, from: JSONEncoder().encode(english)).documentLanguage, .en)
    }

    @MainActor func testEnglishPDFInEveryTemplateAndMultipage() throws {
        for template in InvoiceTemplate.allCases {
            for long in [false, true] {
                var invoice = Store.seed().invoices[0]
                invoice.language = .en
                invoice.templateOverride = template
                invoice.supplier.vatPayer = true
                invoice.items[0].vatRate = 20
                invoice.items[0].discount = 5
                invoice.items[0].name = "Pôvodný názov položky"
                invoice.note = "Vlastná poznámka zostáva."
                invoice.paid = 0
                if long { invoice.items = (0..<45).map { _ in var item = invoice.items[0]; item.id = UUID(); return item } }
                let before = invoice
                let data = InvoicePDF.render(invoice)
                let document = try XCTUnwrap(PDFDocument(data: data))
                let text = try XCTUnwrap(document.string)
                for label in ["INVOICE", "SUPPLIER", "CUSTOMER", "Payment reference", "Amount due", "VAT", "Discount", "Bank transfer", "Pôvodný názov položky", "Vlastná poznámka zostáva."] {
                    XCTAssertTrue(text.contains(label), "Missing \(label) in \(template)")
                }
                for label in ["FAKTÚRA", "DODÁVATEĽ", "ODBERATEĽ", "Suma na úhradu", "Variabilný symbol", "Vystavil:"] {
                    XCTAssertFalse(text.contains(label), "Untranslated \(label) in \(template)")
                }
                XCTAssertEqual(invoice, before)
                if long { XCTAssertGreaterThan(document.pageCount, 1) }
                if let output = ProcessInfo.processInfo.environment["INVOY_LANGUAGE_QA"] {
                    try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(template.rawValue)-\(long ? "long" : "short").pdf"))
                }
                invoice.language = .sk
                XCTAssertTrue(PDFDocument(data: InvoicePDF.render(invoice))!.string!.contains("FAKTÚRA"))
            }
        }
    }
}
