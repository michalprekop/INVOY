import { api } from './api';
import type { InvoiceSummary, SavedInvoice } from '../shared/model';

type SummaryPage = { items: InvoiceSummary[]; nextOffset: number | null };
type ReadAPI = <T>(path: string, options?: RequestInit) => Promise<T>;

export async function loadExportInvoices(signal: AbortSignal, read: ReadAPI = api) {
  const invoices = new Map<string, InvoiceSummary>();
  let offset: number | null = 0;
  do {
    signal.throwIfAborted();
    const page: SummaryPage = await read(`/invoices?trash=0&offset=${offset}`, { signal });
    for (const invoice of page.items) {
      if (!invoice.deleted_at) invoices.set(invoice.id, invoice);
    }
    if (page.nextOffset !== null && page.nextOffset <= offset)
      throw Error('Zoznam faktúr sa nepodarilo načítať. Skúste export znova.');
    offset = page.nextOffset;
  } while (offset !== null);
  return [...invoices.values()];
}

export function exportYears(invoices: InvoiceSummary[]) {
  return [...new Set(invoices.map((i) => i.issueDate?.slice(0, 4)).filter(Boolean))]
    .sort()
    .reverse() as string[];
}

export function selectExportInvoices(invoices: InvoiceSummary[], year: string) {
  return invoices
    .filter((i) => !i.deleted_at && (!year || i.issueDate?.startsWith(`${year}-`)))
    .sort(
      (a, b) =>
        (a.issueDate ?? '').localeCompare(b.issueDate ?? '') ||
        a.number.localeCompare(b.number, 'sk', { numeric: true }) ||
        a.id.localeCompare(b.id),
    );
}

/** Fetch one saved snapshot at a time; never silently omit changed or deleted invoices. */
export async function* exportSnapshots(
  invoices: InvoiceSummary[],
  signal: AbortSignal,
  read: ReadAPI = api,
): AsyncGenerator<SavedInvoice> {
  for (const summary of invoices) {
    signal.throwIfAborted();
    const invoice = await read<SavedInvoice>(`/invoices/${summary.id}`, { signal });
    if (invoice.deletedAt || invoice.version !== summary.version)
      throw Error(`Faktúra ${summary.number} sa medzitým zmenila. Skúste export znova.`);
    signal.throwIfAborted();
    yield invoice;
  }
}
