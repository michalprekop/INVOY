import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { InvoiceEditor } from '../src/InvoiceEditor';
import { invoiceInput, type Profile, type SavedInvoice, type Template } from '../shared/model';
import { toNativeInvoice } from '../shared/native';
import { harness } from './harness';

test('renamed templates display their current catalogue name on old invoices and duplicates', async () => {
  const h = await harness();
  try {
    const source = await h.invoice('owner');
    source.templateID = 'mono';
    const original = (await (
      await h.request('owner', `/api/invoices/${source.id}`, 'PUT', source)
    ).json()) as SavedInvoice;
    assert.equal(original.templateName, 'Mono 01');
    await h.db.prepare("UPDATE templates SET name='Uncut Corners' WHERE id='mono'").run();
    const templates = (await (await h.request('owner', '/api/templates')).json()) as Template[];
    const { profile } = (await (await h.request('owner', '/api/me')).json()) as {
      profile: Profile;
    };
    const label = (invoice: SavedInvoice, choices = templates) => {
      const markup = renderToStaticMarkup(
        createElement(InvoiceEditor, {
          initial: invoice,
          profile,
          templates: choices,
          accountID: h.identities.owner.id,
          onSaved() {},
          onDuplicate() {},
          onDelete() {},
          registerFlush() {},
        }),
      );
      return markup.match(/<button[^>]*aria-label="Šablóna faktúry"[^>]*>(.*?)<\/button>/s)![1];
    };
    assert.match(label(original), /Uncut Corners/);
    assert.doesNotMatch(label(original), /Mono 01/);
    const duplicate = {
      ...invoiceInput(original),
      id: crypto.randomUUID(),
      number: '2026002',
      version: 0,
    };
    const result = await h.request('owner', `/api/invoices/${duplicate.id}`, 'PUT', duplicate);
    assert.equal(result.status, 200);
    const saved = (await result.json()) as SavedInvoice;
    assert.equal(saved.templateID, original.templateID);
    assert.equal(saved.templateName, 'Uncut Corners');
    assert.match(label(saved), /Uncut Corners/);
    assert.equal(toNativeInvoice(saved).cloudStyle?.name, 'Uncut Corners');
    const unchanged = (await (
      await h.request('owner', `/api/invoices/${source.id}`)
    ).json()) as SavedInvoice;
    assert.deepEqual(unchanged, { ...original, deletedAt: null });
    // Removed templates still show the invoice's historical name.
    assert.match(label(original, []), /Mono 01/);
  } finally {
    await h.mf.dispose();
  }
});
