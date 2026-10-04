import test from 'node:test';
import assert from 'node:assert/strict';
import type { InvoiceSummary, SavedInvoice } from '../shared/model';
import {
  exportSnapshots,
  exportYears,
  loadExportInvoices,
  selectExportInvoices,
} from '../src/invoice-export';

const summary = (id: string, date: string, number = id): InvoiceSummary => ({
  id,
  number,
  issueDate: date,
  updated_at: '2026-10-05',
  dueDate: '2027-01-01',
  version: 1,
  customer: 'Vzor',
  total: '10',
  currency: 'EUR',
  paid: '0',
  deleted_at: null,
});

test('year export follows issue date, includes all payment states and sorts chronologically', () => {
  const rows = [
    summary('b', '2026-12-31', 'FA-10'),
    summary('old', '2025-12-31', '2026001'),
    { ...summary('a', '2026-01-01'), paid: '10' },
    summary('c', '2026-12-31', 'FA-2'),
    { ...summary('trash', '2026-01-01'), deleted_at: '2026-10-05' },
  ];
  assert.deepEqual(exportYears(rows), ['2026', '2025']);
  assert.deepEqual(
    selectExportInvoices(rows, '2026').map((i) => i.id),
    ['a', 'c', 'b'],
  );
  assert.deepEqual(
    selectExportInvoices(rows, '').map((i) => i.id),
    ['old', 'a', 'c', 'b'],
  );
  assert.deepEqual(selectExportInvoices(rows, '2024'), []);
});

test('export loads more than 100 invoices and always requests the non-trash collection', async () => {
  const calls: string[] = [];
  const rows = Array.from({ length: 141 }, (_, i) => summary(String(i), '2026-01-01'));
  const result = await loadExportInvoices(new AbortController().signal, async <T>(path: string) => {
    calls.push(path);
    const offset = Number(new URL(path, 'https://test').searchParams.get('offset'));
    return { items: rows.slice(offset, offset + 100), nextOffset: offset === 0 ? 100 : null } as T;
  });
  assert.equal(result.length, 141);
  assert.deepEqual(calls, ['/invoices?trash=0&offset=0', '/invoices?trash=0&offset=100']);
});

test('snapshot loading is lazy and rejects changed or deleted records rather than skipping them', async () => {
  for (const change of [{ version: 2 }, { deletedAt: '2026-10-05' }]) {
    let requests = 0;
    const snapshots = exportSnapshots(
      [summary('a', '2026-01-01'), summary('b', '2026-01-02')],
      new AbortController().signal,
      async <T>() => {
        requests++;
        return { version: 1, ...change } as T;
      },
    );
    assert.equal(requests, 0);
    await assert.rejects(snapshots.next(), /sa medzitým zmenila/);
    assert.equal(requests, 1);
  }
});

test('cancelling stops further snapshot requests', async () => {
  const controller = new AbortController();
  const snapshots = exportSnapshots(
    [summary('a', '2026-01-01'), summary('b', '2026-01-02')],
    controller.signal,
    async <T>() => ({ version: 1 }) as SavedInvoice as T,
  );
  assert.equal((await snapshots.next()).done, false);
  controller.abort();
  await assert.rejects(snapshots.next(), { name: 'AbortError' });
});
