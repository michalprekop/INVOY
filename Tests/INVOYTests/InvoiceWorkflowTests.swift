import XCTest
import InvoiceCore
@testable import INVOY

final class InvoiceWorkflowTests: XCTestCase {
    @MainActor func testPaperDraftRecalculatesWithoutWritingUntilSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(dataDirectory: directory, initialDatabase: Store.seed())
        let before = try Data(contentsOf: store.url)
        let source = try XCTUnwrap(store.database.invoices.first)
        let draft = InvoiceDraft(store.duplicate(source), isNew: true)
        draft.invoice.items[0].quantity = 2
        draft.invoice.items[0].unitPrice = Decimal(string: "250.50")!
        XCTAssertTrue(draft.hasChanges)
        XCTAssertEqual(draft.invoice.total, 501)
        XCTAssertEqual(draft.invoice.remaining, 501)
        XCTAssertNotNil(try PaymentQR.make(for: draft.invoice))
        XCTAssertEqual(try Data(contentsOf: store.url), before)
        XCTAssertTrue(draft.save(to: store))
        XCTAssertFalse(draft.hasChanges)
        XCTAssertFalse(draft.isNew)
        XCTAssertEqual(store.database.invoices.first { $0.id == source.id }, source)
        XCTAssertEqual(store.database.invoices.first { $0.id == draft.invoice.id }?.total, 501)
        XCTAssertEqual(store.newInvoice().number, "2026027")
    }

    @MainActor func testInvalidPaperInputBlocksSaveAndRemovingRowClearsOnlyItsErrors() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(dataDirectory: directory, initialDatabase: Store.seed())
        let source = try XCTUnwrap(store.database.invoices.first)
        let draft = InvoiceDraft(source)
        XCTAssertFalse(draft.hasChanges)
        let before = try Data(contentsOf: store.url)
        let extra = InvoiceItem()
        draft.invoice.items.append(extra)
        draft.invalid = ["p" + extra.id.uuidString, "paid"]
        XCTAssertFalse(draft.save(to: store))
        XCTAssertEqual(try Data(contentsOf: store.url), before)
        draft.removeItem(extra.id)
        XCTAssertEqual(draft.invalid, ["paid"])
        XCTAssertTrue(draft.hasChanges)
        draft.invalid.removeAll()
        XCTAssertFalse(draft.hasChanges)
        draft.removeItem(source.items[0].id)
        XCTAssertEqual(draft.invoice.items.count, 1)
    }

    @MainActor func testNewAndDuplicateUsePaymentStatusWithoutChangingOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(dataDirectory: directory, initialDatabase: Store.seed())
        let originalData = try Data(contentsOf: store.url)
        let source = try XCTUnwrap(store.database.invoices.first)
        var fresh = store.newInvoice()
        fresh.items[0].unitPrice = 100
        let duplicate = store.duplicate(source)
        XCTAssertEqual(fresh.status, "Na úhradu")
        XCTAssertEqual(duplicate.status, "Na úhradu")
        XCTAssertNotEqual(source.id, duplicate.id)
        XCTAssertEqual(duplicate.number, fresh.number)
        XCTAssertEqual(duplicate.customer, source.customer)
        XCTAssertEqual(duplicate.items.first?.name, source.items.first?.name)
        XCTAssertEqual(duplicate.paid, 0)
        XCTAssertEqual(try Data(contentsOf: store.url), originalData)
        XCTAssertTrue(store.save(duplicate))
        let restored = Store(dataDirectory: directory, initialDatabase: Store.seed())
        XCTAssertEqual(restored.database.invoices.count, 2)
        XCTAssertEqual(restored.database.invoices.first { $0.id == source.id }, source)
        XCTAssertEqual(restored.database.invoices.first { $0.id == duplicate.id }?.number, fresh.number)
    }

    @MainActor func testDuplicatingRenamedCloudTemplateUsesCatalogueNameWithoutChangingSavedDesign() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(dataDirectory: directory, initialDatabase: Store.seed())
        var source = try XCTUnwrap(store.database.invoices.first)
        let historical = try JSONDecoder().decode(CloudInvoiceStyle.self, from: Data("""
            {"id":"custom-mono","name":"Mono 01","config":{"layout":"mono","accent":"#000000","wordmark":"Original design","logo":"","footer":"Original footer"}}
            """.utf8))
        source.cloudStyle = historical
        source.templateOverride = .mono01
        var renamed = historical
        renamed.name = "Uncut Corners"
        renamed.config.footer = "New catalogue footer"
        var other = renamed
        other.id = "other-mono"
        other.name = "Another mono template"
        store.cloudTemplates = [other, renamed]
        XCTAssertTrue(store.save(source))
        source = try XCTUnwrap(store.database.invoices.first { $0.id == source.id })
        let before = try Data(contentsOf: store.url)
        let copy = store.duplicate(source)
        XCTAssertEqual(store.invoiceTemplateName(source), "Uncut Corners")
        XCTAssertEqual(store.invoiceTemplateName(copy), "Uncut Corners")
        XCTAssertEqual(copy.cloudStyle, historical)
        XCTAssertEqual(copy.templateOverride, source.templateOverride)
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(try Data(contentsOf: store.url), before)
        XCTAssertTrue(store.save(copy))
        let restored = Store(dataDirectory: directory)
        restored.cloudTemplates = [renamed]
        let saved = try XCTUnwrap(restored.database.invoices.first { $0.id == copy.id })
        XCTAssertEqual(restored.invoiceTemplateName(saved), "Uncut Corners")
        XCTAssertEqual(saved.cloudStyle, historical)
        XCTAssertEqual(restored.database.invoices.first { $0.id == source.id }, source)
        // Another template with the same layout must never substitute its name.
        restored.cloudTemplates = [other]
        XCTAssertEqual(restored.invoiceTemplateName(saved), "Mono 01")
        restored.cloudTemplates = nil
        XCTAssertEqual(restored.invoiceTemplateName(saved), "Mono 01")
        var local = saved
        local.cloudStyle = nil
        XCTAssertEqual(restored.invoiceTemplateName(local), "Mono 01")
    }

    @MainActor func testSavingAnEditUpdatesExistingInvoice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(dataDirectory: directory, initialDatabase: Store.seed())
        var invoice = try XCTUnwrap(store.database.invoices.first)
        invoice.note = "Updated in the main window"
        XCTAssertTrue(store.save(invoice))
        let restored = Store(dataDirectory: directory, initialDatabase: Store.seed())
        XCTAssertEqual(restored.database.invoices.count, 1)
        XCTAssertEqual(restored.database.invoices.first?.id, invoice.id)
        XCTAssertEqual(restored.database.invoices.first?.note, invoice.note)
    }
}
