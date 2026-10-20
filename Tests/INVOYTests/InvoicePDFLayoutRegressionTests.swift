import XCTest
import AppKit
import PDFKit
import InvoiceCore
@testable import INVOY

final class InvoicePDFLayoutRegressionTests: XCTestCase {
    @MainActor func testPaidInvoiceWithWideHeaderAndSignatureFitsOnePage() throws {
        var invoice = Store.seed().invoices[0]
        invoice.language = .en
        invoice.supplier.vatPayer = false
        invoice.items[0].name = "Spravovanie a technická podpora webstránky\nSample.com, október 2026"
        invoice.items[0].unitPrice = 995
        invoice.items[0].detail = ""
        invoice.paid = 995
        invoice.note = "Nie sme platiteľmi DPH."
        invoice.signature = image(width: 480, height: 320)
        let header = image(width: 1100, height: 160)
        invoice.cloudStyle = try JSONDecoder().decode(CloudInvoiceStyle.self, from: JSONSerialization.data(withJSONObject: [
            "id": "test", "name": "Sample Studio", "config": ["layout": "mono", "accent": "#000000", "wordmark": "", "footer": "", "logo": "data:image/png;base64," + header.base64EncodedString()]
        ]))
        let pdf = InvoicePDF.render(invoice)
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertEqual(document.pageCount, 1)
        for label in ["Total amount", "Paid", "Amount due", "Signature and stamp", "We are not VAT registered."] {
            XCTAssertTrue(document.page(at: 0)?.string?.contains(label) == true, label)
        }
        if let output = ProcessInfo.processInfo.environment["INVOY_PDF_LAYOUT_QA"] {
            try pdf.write(to: URL(fileURLWithPath: output).appendingPathComponent("native-paid.pdf"))
        }
    }

    @MainActor private func image(width: Int, height: Int) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.systemGreen.setStroke()
        let border = NSBezierPath(rect: NSRect(x: 4, y: 4, width: width - 8, height: height - 8)); border.lineWidth = 4; border.stroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: 20, y: 20, width: 100, height: 100)); circle.lineWidth = 4; circle.stroke()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
}
