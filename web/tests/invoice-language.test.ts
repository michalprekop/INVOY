import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { InvoicePaper } from '../src/InvoicePaper';
import { baseConfig, freshInvoice, emptyProfile, invoiceSchema } from '../shared/model';

test('English labels render in every PDF template without changing invoice data', () => {
  const invoice = freshInvoice(emptyProfile(), '2026001', 'classic');
  invoice.language = 'en';
  invoice.supplier.name = 'Dodávateľ s.r.o.';
  invoice.customer.name = 'Odberateľ s.r.o.';
  invoice.items[0].name = 'Pôvodná položka';
  invoice.items[0].discount = '5';
  invoice.supplier.vatPayer = true;
  invoice.note = 'Vlastná poznámka.';
  invoice.issuedBy = 'Test Person';
  const before = structuredClone(invoice);
  for (const layout of ['classic', 'mono', 'manoloBay'] as const) {
    const html = renderToStaticMarkup(
      createElement(InvoicePaper, { invoice, theme: { ...baseConfig, layout } }),
    );
    for (const label of [
      'INVOICE',
      'SUPPLIER',
      'CUSTOMER',
      'Payment reference',
      'Amount due',
      'VAT',
      'Discount',
      'Issued by',
      'Pôvodná položka',
      'Vlastná poznámka.',
    ])
      assert.ok(html.includes(label), `${layout}: ${label}`);
    for (const label of [
      'FAKTÚRA',
      'DODÁVATEĽ',
      'ODBERATEĽ',
      'Variabilný symbol',
      'Suma na úhradu',
      'Vystavil:',
    ])
      assert.ok(!html.includes(label), `${layout}: ${label}`);
  }
  assert.deepEqual(invoice, before);
  delete invoice.language;
  const html = renderToStaticMarkup(createElement(InvoicePaper, { invoice, theme: baseConfig }));
  assert.ok(html.includes('FAKTÚRA'));
  assert.ok(!invoiceSchema.safeParse({ ...invoice, language: 'de' }).success);
});
