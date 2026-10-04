import XCTest
import PDFKit
import InvoiceCore
@testable import INVOY

final class InvoiceBatchExportTests: XCTestCase {
    @MainActor func testSelectionUsesIssueYearAndChronologicalOrder() {
        let seed = Store.seed().invoices[0]
        func invoice(_ number: String, _ year: Int, _ month: Int) -> Invoice {
            var value = seed
            value.id = UUID(); value.number = number
            value.issueDate = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))!
            return value
        }
        let invoices = [invoice("FA-10", 2026, 12), invoice("2026001", 2025, 12), invoice("FA-2", 2026, 12), invoice("FA-1", 2026, 1)]
        XCTAssertEqual(InvoiceExportSelection.years(invoices), [2026, 2025])
        XCTAssertEqual(InvoiceExportSelection.invoices(invoices, year: 2026).map(\.number), ["FA-1", "FA-2", "FA-10"])
        XCTAssertEqual(InvoiceExportSelection.invoices(invoices, year: 0).count, 4)
        XCTAssertTrue(InvoiceExportSelection.invoices(invoices, year: 2024).isEmpty)
    }

    @MainActor func testCombinedPDFPreservesEveryPageAcrossTemplates() async throws {
        let seed = Store.seed().invoices[0]
        let invoices: [Invoice] = [InvoiceTemplate.boringDefault01, .mono01, .manoloBay].enumerated().map { index, template in
            var invoice = seed
            invoice.id = UUID(); invoice.number = "202600\(index + 1)"; invoice.templateOverride = template
            if index == 1 {
                invoice.items = (1...40).map { number in
                    var item = seed.items[0]; item.id = UUID(); item.name = "Dlhá faktúra – položka \(number)"; return item
                }
            }
            return invoice
        }
        let originals = try invoices.map { try XCTUnwrap(PDFDocument(data: InvoicePDF.render($0))) }
        XCTAssertGreaterThan(originals[1].pageCount, 1)
        let data = try await InvoiceBatchPDFRenderer.shared.render(invoices, accent: .standard, template: .boringDefault01, title: "Faktúry – všetky roky")
        let combined = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(combined.pageCount, originals.reduce(0) { $0 + $1.pageCount })
        var offset = 0
        for (index, original) in originals.enumerated() {
            XCTAssertTrue(combined.page(at: offset)?.string?.contains(invoices[index].number) == true)
            for page in 0..<original.pageCount {
                XCTAssertEqual(combined.page(at: offset + page)?.string, original.page(at: page)?.string)
                XCTAssertEqual(combined.page(at: offset + page)?.bounds(for: .mediaBox), original.page(at: page)?.bounds(for: .mediaBox))
            }
            offset += original.pageCount
        }
        if let directory = ProcessInfo.processInfo.environment["INVOY_BATCH_QA_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try data.write(to: url.appendingPathComponent("mixed-templates.pdf"))
        }
    }

    func testEmptyBatchIsRejected() async {
        do {
            _ = try await InvoiceBatchPDFRenderer.shared.render([], accent: .standard, template: .boringDefault01, title: "Prázdne")
            XCTFail("Empty PDF must not be exported")
        } catch {}
    }
}
