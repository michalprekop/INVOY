import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { harness } from './harness';
import { toNativeInvoice, toNativeSettings, fromNativeInvoice } from '../shared/native';
import { baseConfig, totals, type SavedInvoice, type Profile } from '../shared/model';
let h: Awaited<ReturnType<typeof harness>>;
before(async () => {
  h = await harness();
});
after(async () => {
  await h.mf.dispose();
});
async function fixture(who = 'alice') {
  const i = await h.invoice(who);
  i.customer.id = crypto.randomUUID();
  i.supplier.id = crypto.randomUUID();
  i.orderNumber = 'OBJ-123';
  i.items[0].detail = 'Prvá časť\nDruhá časť';
  i.paid = '25';
  const native = toNativeInvoice({
    ...i,
    updatedAt: '2026-09-20T12:00:00Z',
    templateSnapshot: baseConfig,
    templateName: 'Classic',
  });
  const me = (await (await h.request(who, '/api/me')).json()) as { profile: Profile };
  return {
    schemaVersion: 1 as const,
    settings: toNativeSettings(me.profile),
    customers: [native.customer],
    invoices: [native],
  };
}
test('native import is tenant-scoped, atomic and idempotent', async () => {
  const source = await fixture();
  const response = await h.request('alice', '/api/native/import', 'POST', source);
  assert.equal(response.status, 200, await response.clone().text());
  assert.equal(((await response.json()) as { imported: number }).imported, 1);
  const again = await h.request('alice', '/api/native/import', 'POST', source);
  assert.equal(again.status, 200);
  assert.equal(((await again.json()) as { alreadyImported: boolean }).alreadyImported, true);
  const id = source.invoices[0].id;
  assert.equal((await h.request('bob', '/api/native/invoices/' + id)).status, 404);
  const bob = (await h.request('bob', '/api/export').then((r) => r.json())) as {
    invoices: unknown[];
  };
  assert.equal(bob.invoices.length, 0);
  const saved = (await (await h.request('alice', '/api/invoices/' + id)).json()) as SavedInvoice;
  assert.equal(saved.orderNumber, 'OBJ-123');
  assert.equal(saved.items[0].detail, source.invoices[0].items[0].detail);
  assert.equal(saved.paid, '25');
  assert.equal(
    totals(saved).total,
    totals(fromNativeInvoice(source.invoices[0], 0, 'classic')).total,
  );
  const restored = (await (
    await h.request('alice', '/api/native/invoices/' + id.toUpperCase())
  ).json()) as { invoice: (typeof source.invoices)[0] };
  assert.deepEqual(restored.invoice.customer, source.invoices[0].customer);
  assert.deepEqual(restored.invoice.items, source.invoices[0].items);
  assert.equal(restored.invoice.issueDate, source.invoices[0].issueDate);
  assert.equal(restored.invoice.orderNumber, 'OBJ-123');
  source.invoices[0].note = 'Zmenený import';
  assert.equal((await h.request('alice', '/api/native/import', 'POST', source)).status, 409);
});
test('native importer refuses occupied accounts without changing profile or invoices', async () => {
  const i = await h.invoice('bob');
  assert.equal((await h.request('bob', '/api/invoices/' + i.id, 'PUT', i)).status, 200);
  const profileBefore = await h.request('bob', '/api/native/profile').then((r) => r.json());
  const source = await fixture('bob');
  source.settings.supplier.name = 'Overwrite attempt';
  assert.equal((await h.request('bob', '/api/native/import', 'POST', source)).status, 409);
  assert.deepEqual(
    await h.request('bob', '/api/native/profile').then((r) => r.json()),
    profileBefore,
  );
  const row = await h.db
    .prepare('SELECT count(*) AS n FROM native_imports WHERE user_id=?')
    .bind(h.identities.bob.id)
    .first<{ n: number }>();
  assert.equal(row?.n, 0);
});
test('native writes enforce CSRF, grants and optimistic versions', async () => {
  const source = await fixture('owner');
  assert.equal(
    (await h.request('owner', '/api/native/import', 'POST', source, { 'X-CSRF-Token': 'wrong' }))
      .status,
    403,
  );
  assert.equal((await h.request('pending', '/api/native/import', 'POST', source)).status, 403);
  const n = source.invoices[0],
    path = '/api/native/invoices/' + n.id.toUpperCase();
  assert.equal(
    (
      await h.request('owner', path, 'PUT', {
        invoice: n,
        version: 0,
        templateID: 'private-unassigned',
      })
    ).status,
    403,
  );
  assert.equal(
    (await h.request('owner', path, 'PUT', { invoice: n, version: 0, templateID: 'classic' }))
      .status,
    200,
  );
  assert.equal(
    (await h.request('owner', path, 'PUT', { invoice: n, version: 0, templateID: 'classic' }))
      .status,
    409,
  );
  n.note = 'Úprava z Macu';
  assert.equal(
    (await h.request('owner', path, 'PUT', { invoice: n, version: 1, templateID: 'classic' }))
      .status,
    200,
  );
  const web = (await (await h.request('owner', '/api/invoices/' + n.id)).json()) as SavedInvoice;
  assert.equal(web.note, n.note);
  const { templateSnapshot, templateName, updatedAt, deletedAt, ...input } = web;
  input.note = 'Úprava z webu';
  assert.equal((await h.request('owner', '/api/invoices/' + n.id, 'PUT', input)).status, 200);
  const mac = (await (await h.request('owner', path)).json()) as {
    invoice: typeof n;
    version: number;
  };
  assert.equal(mac.invoice.note, input.note);
  assert.equal(mac.version, 3);
});

test('invoice language persists from web through native edits and back', async () => {
  const invoice = await h.invoice('alice');
  invoice.number = 'LANG-2026001';
  invoice.language = 'en';
  const put = await h.request('alice', '/api/invoices/' + invoice.id, 'PUT', invoice);
  assert.equal(put.status, 200, await put.clone().text());
  const saved = (await (
    await h.request('alice', '/api/invoices/' + invoice.id)
  ).json()) as SavedInvoice;
  assert.equal(saved.language, 'en');
  const native = toNativeInvoice(saved);
  assert.equal(native.language, 'en');
  assert.equal(fromNativeInvoice(native, saved.version, saved.templateID).language, 'en');
  native.language = 'sk';
  assert.equal(fromNativeInvoice(native, saved.version, saved.templateID).language, 'sk');
  delete native.language;
  assert.equal(fromNativeInvoice(native, saved.version, saved.templateID).language, undefined);
});
