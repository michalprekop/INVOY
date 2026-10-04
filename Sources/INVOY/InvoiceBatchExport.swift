import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import InvoiceCore

enum InvoiceExportSelection {
    static func years(_ invoices: [Invoice]) -> [Int] {
        Array(Set(invoices.map { Calendar.current.component(.year, from: $0.issueDate) })).sorted(by: >)
    }

    static func invoices(_ invoices: [Invoice], year: Int) -> [Invoice] {
        invoices.filter { year == 0 || Calendar.current.component(.year, from: $0.issueDate) == year }
            .sorted {
                if $0.issueDate != $1.issueDate { return $0.issueDate < $1.issueDate }
                if $0.number != $1.number { return $0.number.localizedStandardCompare($1.number) == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
}

/// Rendering and merging run away from the UI thread, preserving vector pages and every template.
actor InvoiceBatchPDFRenderer {
    static let shared = InvoiceBatchPDFRenderer()

    func render(_ invoices: [Invoice], accent: InvoiceAccent, template: InvoiceTemplate,
                title: String, onProgress: @Sendable (Int) async -> Void = { _ in }) async throws -> Data {
        guard !invoices.isEmpty else { throw DataError.invalid("Pre zvolené obdobie nie sú žiadne faktúry.") }
        let combined = PDFDocument()
        combined.documentAttributes = [PDFDocumentAttribute.titleAttribute: title, PDFDocumentAttribute.creatorAttribute: "INVOY"]
        for (index, invoice) in invoices.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                _ = try PaymentQR.make(for: invoice)
                let data = InvoicePDF.render(invoice, accentColor: accent, defaultTemplate: template)
                guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                    throw DataError.invalid("PDF faktúry \(invoice.number) sa nepodarilo vytvoriť.")
                }
                for pageIndex in 0..<document.pageCount {
                    guard let page = document.page(at: pageIndex)?.copy() as? PDFPage else {
                        throw DataError.invalid("Stranu faktúry \(invoice.number) sa nepodarilo pridať.")
                    }
                    combined.insert(page, at: combined.pageCount)
                }
            }
            await onProgress(index + 1)
        }
        try Task.checkCancellation()
        guard let data = combined.dataRepresentation() else { throw DataError.invalid("PDF sa nepodarilo vytvoriť.") }
        return data
    }
}

struct InvoiceExportSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let initialYear: Int
    @State private var year = 0
    @State private var exporting = false
    @State private var completed = 0
    @State private var total = 0
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private var years: [Int] { InvoiceExportSelection.years(store.invoices) }
    private var selected: [Invoice] { InvoiceExportSelection.invoices(store.invoices, year: year) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Exportovať faktúry").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { task?.cancel(); dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Zavrieť")
            }
            Text("Faktúry podľa dátumu vystavenia. Každá začne na novej strane.")
                .font(.system(size: 13)).foregroundStyle(InvoyBrand.ink.opacity(0.6))
            VStack(alignment: .leading, spacing: 5) {
                Text("Rok").font(.system(size: 11)).foregroundStyle(InvoyBrand.ink.opacity(0.6))
                BrandDropdown(title: "Rok exportu", value: year == 0 ? "Všetky roky" : String(year), items: ([0] + years).map { option in
                    BrandDropdownItem(title: option == 0 ? "Všetky roky" : String(option), selected: year == option) { year = option }
                }).disabled(exporting)
            }
            Text(exporting ? "Pripravujem PDF… \(completed) / \(total)" : "Počet faktúr: \(selected.count) · jedno PDF")
                .font(.system(size: 13)).foregroundStyle(InvoyBrand.ink.opacity(0.6))
            if let error { Text(error).font(.system(size: 13)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 10) {
                Spacer()
                Button("Zrušiť") { task?.cancel(); dismiss() }.buttonStyle(BrandSecondaryButtonStyle())
                Button { export() } label: { Label("Export PDF", systemImage: "square.and.arrow.down") }
                    .buttonStyle(BrandButtonStyle()).disabled(exporting || selected.isEmpty)
            }.padding(.top, 8)
        }
        .padding(27).frame(width: 540).foregroundStyle(InvoyBrand.ink).background(Color.white)
        .environment(\.colorScheme, .light)
        .onAppear { year = years.contains(initialYear) ? initialYear : years.first ?? 0 }
        .onDisappear { task?.cancel() }
    }

    private func export() {
        error = nil
        guard store.flushInvoices(), store.flushSettings() else {
            error = "Pred exportom dokončite a uložte rozpracované údaje."; return
        }
        let invoices = selected
        guard !invoices.isEmpty else { return }
        for invoice in invoices {
            if store.invoiceRecovery.contains(where: { $0.id == invoice.id }) || invoice.validation(existing: store.invoices) != nil {
                error = "Pred exportom dokončite údaje faktúry \(invoice.number). Rozpracovaná verzia je uložená."
                return
            }
        }
        let panel = NSSavePanel()
        panel.title = "Uložiť PDF"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Faktury-\(year == 0 ? "vsetky-roky" : String(year)).pdf"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        let settings = store.database.settings
        let title = "Faktúry – \(year == 0 ? "všetky roky" : String(year))"
        total = invoices.count; completed = 0; exporting = true
        task = Task { @MainActor in
            do {
                let data = try await InvoiceBatchPDFRenderer.shared.render(invoices, accent: settings.invoiceAccent,
                    template: settings.defaultInvoiceTemplate, title: title) { count in
                    await MainActor.run { completed = count }
                }
                try Task.checkCancellation()
                try data.write(to: target, options: .atomic)
                store.notice = "PDF je uložené."
                dismiss()
            } catch is CancellationError {
                // Cancelling never writes a partial document.
            } catch { self.error = error.localizedDescription }
            exporting = false
        }
    }
}
