import { invoiceText } from '../shared/invoice-language';
import { BrandSelect } from './BrandSelect';
import { manoloBay } from '../shared/manolo-bay';
import { A4Paper } from './A4Paper';
import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { createPortal } from 'react-dom';
import QRCode from 'qrcode';
import { encode, CurrencyCode, PaymentOptions } from 'bysquare/pay';
import {
  displayDate,
  money,
  totals,
  type Invoice,
  type TemplateConfig,
  type Company,
  type Profile,
} from '../shared/model';

export function paymentPayload(invoice: Invoice): string | null {
  const sum = totals(invoice);
  if (
    !invoice.account ||
    Number(sum.remaining) <= 0 ||
    invoice.paymentMethod !== 'Bankový prevod' ||
    invoice.qrFormat === 'disabled'
  )
    return null;
  const account = invoice.account,
    iban = account.iban.replace(/\s/g, '').toUpperCase();
  const czech =
    invoice.qrFormat === 'qrPlatba' ||
    (invoice.qrFormat === 'automatic' &&
      /^(CZ|Česko|Česká republika|Czechia)$/i.test(invoice.customer.country));
  const safe = (v: string) =>
    v
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^A-Za-z0-9 .\-]/g, '')
      .slice(0, 60);
  if (czech)
    return (
      `SPD*1.0*ACC:${iban}*AM:${sum.remaining}*CC:${invoice.currency}*MSG:${safe('Faktura ' + invoice.number)}` +
      (invoice.variableSymbol ? `*X-VS:${invoice.variableSymbol}` : '') +
      (invoice.constantSymbol ? `*X-KS:${invoice.constantSymbol}` : '') +
      (invoice.specificSymbol ? `*X-SS:${invoice.specificSymbol}` : '')
    );
  return encode({
    payments: [
      {
        type: PaymentOptions.PaymentOrder,
        amount: Number(sum.remaining),
        currencyCode: invoice.currency as CurrencyCode,
        variableSymbol: invoice.variableSymbol || undefined,
        constantSymbol: invoice.constantSymbol || undefined,
        specificSymbol: invoice.specificSymbol || undefined,
        paymentNote: 'Faktura ' + invoice.number,
        beneficiary: { name: account.holderName || invoice.supplier.name },
        bankAccounts: [{ iban, bic: account.swift || undefined }],
      },
    ],
  });
}
import { CompanyFields, Modal } from './ui';
import { MoreHorizontal, Plus, Trash2 } from 'lucide-react';

type Edit = { update: (change: Partial<Invoice>) => void; profile: Profile };
function Inline({
  label,
  value,
  onChange,
  numeric = false,
  multiline = false,
  placeholder,
  displayValue,
}: {
  label: string;
  value: string;
  onChange?: (v: string) => void;
  numeric?: boolean;
  multiline?: boolean;
  placeholder?: string;
  displayValue?: string;
}) {
  const [focused, setFocused] = useState(false);
  const shown = !focused && displayValue !== undefined ? displayValue : value;
  if (!onChange) return <span className={numeric ? 'numeric' : ''}>{displayValue ?? value}</span>;
  return multiline ? (
    <textarea
      aria-label={label}
      className="paper-inline"
      value={shown}
      onFocus={() => setFocused(true)}
      onBlur={() => setFocused(false)}
      rows={Math.max(1, value.split('\n').length)}
      onChange={(e) => onChange(e.target.value)}
      onInput={(e) => {
        e.currentTarget.style.height = 'auto';
        e.currentTarget.style.height = e.currentTarget.scrollHeight + 'px';
      }}
      ref={(node) => {
        if (node) {
          node.style.height = 'auto';
          node.style.height = node.scrollHeight + 'px';
        }
      }}
    />
  ) : (
    <input
      aria-label={label}
      className={'paper-inline ' + (numeric ? 'numeric' : '')}
      value={shown}
      onFocus={() => setFocused(true)}
      onBlur={() => setFocused(false)}
      placeholder={placeholder ?? label.split(' – ').at(-1)}
      inputMode={numeric ? 'decimal' : undefined}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}
function Party({
  value,
  title,
  supplier = false,
  onChange,
  profile,
  t,
}: {
  t: (value: string) => string;
  value: Company;
  title: string;
  supplier?: boolean;
  onChange?: (v: Company) => void;
  profile?: Profile;
}) {
  const [details, setDetails] = useState(false);
  const field = (key: keyof Company, label: string, numeric = false) => (
    <Inline
      label={title + ' – ' + t(label)}
      value={String(value[key] ?? '')}
      numeric={numeric}
      multiline={['name', 'street', 'city'].includes(key)}
      placeholder={['companyID', 'taxID', 'vatID'].includes(key) ? '—' : undefined}
      onChange={onChange ? (v) => onChange({ ...value, [key]: v }) : undefined}
    />
  );
  return (
    <section className="original-party">
      <h3>
        {title}
        {onChange && (
          <span className="party-controls">
            <button
              data-tooltip={'Nastavenia ' + (supplier ? 'dodávateľa' : 'odberateľa')}
              aria-label={'Nastavenia ' + (supplier ? 'dodávateľa' : 'odberateľa')}
              onClick={() => setDetails(true)}
            >
              <MoreHorizontal size={15} />
            </button>
            {profile && (
              <BrandSelect
                aria-label="Vybrať odberateľa"
                value=""
                onValueChange={(value) => {
                  const c = profile.customers?.find((c) => c.id === value);
                  if (c) onChange(c);
                }}
              >
                <option value="">⌄</option>
                {profile.customers?.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </BrandSelect>
            )}
          </span>
        )}
      </h3>
      <strong>{field('name', 'Názov / meno')}</strong>
      <div>{field('street', 'Ulica a číslo')}</div>
      <div className="address-line">
        {field('postalCode', 'PSČ')}
        {field('city', 'Mesto')}
      </div>
      <div>{field('country', 'Krajina')}</div>
      <div className="identifiers">
        {(['companyID', 'taxID', 'vatID'] as const).map(
          (k, i) =>
            (value[k] || (onChange && (k !== 'vatID' || value.vatPayer))) && (
              <div key={k}>
                <span>{t(['IČO', 'DIČ', 'IČ DPH'][i])}:</span>
                {field(k, ['IČO', 'DIČ', 'IČ DPH'][i], true)}
              </div>
            ),
        )}
      </div>
      {details && (
        <Modal title={supplier ? 'Dodávateľ' : 'Odberateľ'} onClose={() => setDetails(false)}>
          <CompanyFields value={value} onChange={onChange!} />
          <button className="button" onClick={() => setDetails(false)}>
            Hotovo
          </button>
        </Modal>
      )}
    </section>
  );
}
export function InvoicePaper({
  invoice,
  theme,
  edit,
}: {
  invoice: Invoice;
  theme: TemplateConfig;
  templateName?: string;
  edit?: Edit;
}) {
  const t = (value: string) => invoiceText(invoice.language, value);
  const sum = totals(invoice),
    manolo = theme.layout === 'manoloBay',
    mono = theme.layout === 'mono' || manolo;
  const [qr, setQR] = useState(''),
    [qrError, setQRError] = useState('');
  const [itemMenu, setItemMenu] = useState<{ id: string; x: number; y: number } | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const menuItem = invoice.items.find((item) => item.id === itemMenu?.id);
  useEffect(() => {
    if (!itemMenu) return;
    menuRef.current?.querySelector('input')?.focus({ preventScroll: true });
    const outside = (event: Event) => {
      if (event.target instanceof Node && !menuRef.current?.contains(event.target))
        setItemMenu(null);
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setItemMenu(null);
    };
    const close = () => setItemMenu(null);
    document.addEventListener('pointerdown', outside, true);
    document.addEventListener('keydown', escape);
    window.addEventListener('resize', close);
    document.addEventListener('wheel', outside, { passive: true });
    return () => {
      document.removeEventListener('pointerdown', outside, true);
      document.removeEventListener('keydown', escape);
      window.removeEventListener('resize', close);
      document.removeEventListener('wheel', outside);
    };
  }, [itemMenu]);
  useEffect(() => {
    let active = true;
    setQR('');
    setQRError('');
    if (edit) return;
    try {
      const payload = paymentPayload(invoice);
      if (payload)
        void QRCode.toDataURL(payload, { width: 280, margin: 2, errorCorrectionLevel: 'M' })
          .then((v) => {
            if (active) setQR(v);
          })
          .catch(() => {
            if (active) setQRError('QR sa nepodarilo vytvoriť.');
          });
    } catch {
      setQRError('Skontrolujte platobné údaje.');
    }
    return () => {
      active = false;
    };
  }, [invoice, Boolean(edit)]);
  const field = (
    key:
      | 'number'
      | 'variableSymbol'
      | 'constantSymbol'
      | 'specificSymbol'
      | 'orderNumber'
      | 'note'
      | 'issuedBy'
      | 'paid',
    label: string,
    numeric = false,
    multiline = false,
  ) => (
    <Inline
      label={t(label)}
      value={invoice[key] ?? ''}
      displayValue={
        key === 'note' && invoice.note === 'Nie sme platiteľmi DPH.'
          ? t(invoice.note)
          : (invoice[key] ?? '')
      }
      onChange={edit ? (v) => edit.update({ [key]: numeric ? v.replace(',', '.') : v }) : undefined}
      numeric={numeric}
      multiline={multiline}
    />
  );
  return (
    <A4Paper>
      <article
        className={
          'invoice-paper original-paper ' +
          (manolo ? 'mono manoloBay' : theme.layout) +
          (edit ? ' editable-paper' : '')
        }
        style={{ '--invoice-accent': manolo ? manoloBay.accent : theme.accent } as CSSProperties}
        aria-label={edit ? 'Upraviteľná faktúra' : 'Náhľad faktúry'}
      >
        {manolo && (
          <>
            {/* Keep a physical bottom margin for the repeating footer, including Safari. */}
            <style media="print">{'@page { size: A4; margin: 0 0 10mm; }'}</style>
            <img className="manolo-background" src={manoloBay.background} alt="" />
          </>
        )}
        {manolo ? (
          <div className="manolo-header">
            <img className="manolo-logo" src={manoloBay.logo} alt="Manolo & Bay" />
          </div>
        ) : (
          mono && (
            <div className="original-wordmark">
              {theme.logo ? (
                <img src={theme.logo} alt={theme.wordmark || 'Logo dodávateľa'} />
              ) : (
                theme.wordmark && <strong>{theme.wordmark}</strong>
              )}
            </div>
          )
        )}
        <header className="original-title">
          {mono ? (
            <>
              <div>
                <small>{t('Číslo faktúry')}</small>
                <h1>{field('number', 'Číslo faktúry', true)}</h1>
              </div>
              <b>{t('FAKTÚRA')}</b>
            </>
          ) : (
            <>
              <b>{t('FAKTÚRA')}</b>
              <h1>{field('number', 'Číslo faktúry', true)}</h1>
            </>
          )}
        </header>
        <div className="original-parties">
          <Party
            value={invoice.supplier}
            t={t}
            title={t('DODÁVATEĽ')}
            supplier
            onChange={edit ? (supplier) => edit.update({ supplier }) : undefined}
          />
          <Party
            value={invoice.customer}
            t={t}
            title={t('ODBERATEĽ')}
            onChange={edit ? (customer) => edit.update({ customer }) : undefined}
            profile={edit?.profile}
          />
        </div>
        <div className="original-registration">
          <Inline
            label={t('Zápis v registri')}
            multiline
            value={invoice.supplier.registration}
            onChange={
              edit
                ? (v) => edit.update({ supplier: { ...invoice.supplier, registration: v } })
                : undefined
            }
          />
        </div>
        <div className="original-dates">
          {(['issueDate', 'dueDate', 'deliveryDate'] as const).map(
            (key, i) =>
              (key !== 'deliveryDate' || invoice.deliveryDate) && (
                <div key={key}>
                  <small>{t(['Dátum vystavenia', 'Dátum splatnosti', 'Dátum dodania'][i])}</small>
                  {edit ? (
                    <input
                      aria-label={t(['Dátum vystavenia', 'Dátum splatnosti', 'Dátum dodania'][i])}
                      type="date"
                      value={invoice[key] ?? ''}
                      onChange={(e) => edit.update({ [key]: e.target.value })}
                    />
                  ) : (
                    <span className="numeric">{displayDate(invoice[key] ?? '')}</span>
                  )}
                </div>
              ),
          )}
          <div>
            <small>{t('Forma úhrady')}</small>
            {edit ? (
              <BrandSelect
                aria-label="Forma úhrady"
                value={invoice.paymentMethod}
                onValueChange={(value) =>
                  edit.update({ paymentMethod: value as Invoice['paymentMethod'] })
                }
              >
                {['', 'Bankový prevod', 'Hotovosť', 'Karta', 'Dobierka'].map((v) => (
                  <option key={v} value={v}>
                    {t(v)}
                  </option>
                ))}
              </BrandSelect>
            ) : (
              t(invoice.paymentMethod)
            )}
          </div>
        </div>
        <div className="original-bank">
          {edit ? (
            <BrandSelect
              aria-label="Bankový účet"
              value={invoice.account?.id ?? ''}
              onValueChange={(value) =>
                edit.update({
                  account: edit.profile.accounts.find((a) => a.id === value) ?? null,
                })
              }
            >
              <option value="">Bez účtu</option>
              {invoice.account &&
                !edit.profile.accounts.some((a) => a.id === invoice.account!.id) && (
                  <option value={invoice.account.id}>{invoice.account.iban}</option>
                )}
              {edit.profile.accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.iban.replace(/(.{4})/g, '$1 ')}
                  {a.swift ? ' / ' + a.swift : ''}
                </option>
              ))}
            </BrandSelect>
          ) : (
            invoice.account && (
              <span className="numeric">
                {invoice.account.iban.replace(/(.{4})/g, '$1 ')}
                {invoice.account.swift ? ' / ' + invoice.account.swift : ''}
              </span>
            )
          )}
          <div className="original-symbols">
            <span>{t('Variabilný symbol') + ':'}</span>
            {field('variableSymbol', 'Variabilný symbol', true)}
            {invoice.constantSymbol && (
              <>
                <span>{t('KS:')}</span>
                {field('constantSymbol', 'Konštantný symbol', true)}
              </>
            )}
            {invoice.specificSymbol && (
              <>
                <span>{t('ŠS:')}</span>
                {field('specificSymbol', 'Špecifický symbol', true)}
              </>
            )}
          </div>
          {invoice.orderNumber && (
            <div>
              {t('Objednávka')}: {field('orderNumber', 'Objednávka')}
            </div>
          )}
        </div>
        <table className="original-items">
          <thead>
            <tr>
              <th>{t('POLOŽKA')}</th>
              <th>{t('POČET')}</th>
              <th>{t('JEDNOTKA')}</th>
              <th>{t('CENA / MJ')}</th>
              <th>{t(invoice.supplier.vatPayer ? 'SPOLU S DPH' : 'SPOLU')}</th>
            </tr>
          </thead>
          <tbody>
            {invoice.items.map((item, index) => {
              const change = (key: string, v: string) =>
                edit?.update({
                  items: invoice.items.map((x) =>
                    x.id === item.id
                      ? {
                          ...x,
                          [key]: ['quantity', 'unitPrice', 'discount', 'vatRate'].includes(key)
                            ? v.replace(',', '.')
                            : v,
                        }
                      : x,
                  ),
                });
              return (
                <tr
                  key={item.id}
                  tabIndex={edit ? 0 : undefined}
                  onContextMenu={
                    edit
                      ? (event) => {
                          event.preventDefault();
                          setItemMenu({ id: item.id, x: event.clientX, y: event.clientY });
                        }
                      : undefined
                  }
                  onKeyDown={
                    edit
                      ? (event) => {
                          if (
                            event.key === 'ContextMenu' ||
                            (event.shiftKey && event.key === 'F10')
                          ) {
                            event.preventDefault();
                            const rect = event.currentTarget.getBoundingClientRect();
                            setItemMenu({ id: item.id, x: rect.right - 220, y: rect.top });
                          }
                        }
                      : undefined
                  }
                >
                  <td>
                    <strong>
                      <Inline
                        label={t('Názov položky')}
                        value={item.name}
                        onChange={edit ? (v) => change('name', v) : undefined}
                        multiline
                      />
                    </strong>
                    {(item.detail || edit) && (
                      <div className="item-detail">
                        <Inline
                          label={t('Podrobný popis')}
                          value={item.detail}
                          onChange={edit ? (v) => change('detail', v) : undefined}
                          multiline
                        />
                      </div>
                    )}
                    {Number(item.discount) > 0 && (
                      <small className="item-discount">
                        {t('Zľava')} {item.discount} %
                      </small>
                    )}
                  </td>
                  <td>
                    <Inline
                      label={t('Množstvo')}
                      value={item.quantity}
                      numeric
                      onChange={edit ? (v) => change('quantity', v) : undefined}
                    />
                  </td>
                  <td>
                    <Inline
                      label={t('Jednotka')}
                      value={item.unit}
                      displayValue={t(item.unit)}
                      onChange={edit ? (v) => change('unit', v) : undefined}
                    />
                  </td>
                  <td>
                    <Inline
                      label={t('Cena / MJ')}
                      value={edit ? item.unitPrice : money(item.unitPrice, invoice.currency)}
                      numeric
                      onChange={edit ? (v) => change('unitPrice', v) : undefined}
                    />
                  </td>
                  <td className="numeric">{money(sum.rows[index].total, invoice.currency)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {edit && (
          <div className="original-add">
            <button
              onClick={() =>
                edit.update({
                  items: [
                    ...invoice.items,
                    {
                      id: crypto.randomUUID(),
                      name: '',
                      detail: '',
                      quantity: '1',
                      unit: 'ks',
                      unitPrice: '0',
                      discount: '0',
                      vatRate: edit.profile.defaultVAT,
                    },
                  ],
                })
              }
            >
              <Plus size={15} /> Pridať položku
            </button>
            <BrandSelect
              aria-label="Mena"
              value={invoice.currency}
              onValueChange={(value) => edit.update({ currency: value as Invoice['currency'] })}
            >
              {['EUR', 'CZK', 'USD', 'GBP'].map((v) => (
                <option key={v}>{v}</option>
              ))}
            </BrandSelect>
          </div>
        )}
        <div className="original-closing">
          <div className="original-note">
            {field('note', 'Poznámka', false, true)}
            {!edit && qr && <img className="qr-code" src={qr} alt="Platobný QR kód" />}
            {qrError && <span role="alert">{qrError}</span>}
          </div>
          <section className="original-totals">
            {invoice.supplier.vatPayer && (
              <>
                <p>
                  <span>{t('Základ dane')}</span>
                  <b className="numeric">{money(sum.net, invoice.currency)}</b>
                </p>
                {sum.taxRates.map((r) => (
                  <p key={r.rate}>
                    <span>
                      {t('DPH')} {r.rate} %
                    </span>
                    <b className="numeric">{money(r.vat, invoice.currency)}</b>
                  </p>
                ))}
              </>
            )}
            <p>
              <span>{t('Celková suma')}</span>
              <b className="numeric">{money(sum.total, invoice.currency)}</b>
            </p>
            <p>
              <span>{t('Uhradené')}</span>
              <span>
                {edit ? field('paid', 'Uhradené', true) : money(invoice.paid, invoice.currency)}{' '}
                {edit && invoice.currency}
              </span>
            </p>
            {manolo ? (
              <div className="original-remaining manolo-payment-summary">
                <div>
                  <small>IBAN</small>
                  <strong className="numeric">
                    {invoice.account?.iban.replace(/(.{4})/g, '$1 ').trim() || '—'}
                  </strong>
                </div>
                <div>
                  <small>{t('Variabilný symbol')}</small>
                  <strong className="numeric">{invoice.variableSymbol || '—'}</strong>
                </div>
                <div>
                  <small>{t('Dátum splatnosti')}</small>
                  <strong className="numeric">{displayDate(invoice.dueDate)}</strong>
                </div>
                <div>
                  <small>{t('Suma na úhradu')}</small>
                  <strong className="numeric">{money(sum.remaining, invoice.currency)}</strong>
                </div>
              </div>
            ) : (
              <p className="original-remaining">
                <span>{t('Suma na úhradu')}</span>
                <b className="numeric">{money(sum.remaining, invoice.currency)}</b>
              </p>
            )}
            {Number(sum.overpaid) > 0 && (
              <p>
                <span>{t('Preplatok')}</span>
                <b className="numeric">{money(sum.overpaid, invoice.currency)}</b>
              </p>
            )}
            <small>{t('Podpis a pečiatka')}</small>
            {invoice.signature && (
              <img className="signature" src={invoice.signature} alt="Podpis a pečiatka" />
            )}
          </section>
        </div>
        {!mono && (
          <div className="original-payment-band">
            {[
              ['IBAN', invoice.account?.iban.replace(/(.{4})/g, '$1 ') ?? t(invoice.paymentMethod)],
              ['Variabilný symbol', invoice.variableSymbol],
              ['Splatnosť', displayDate(invoice.dueDate)],
              ['Na úhradu', money(sum.remaining, invoice.currency)],
            ].map(([label, value]) => (
              <div key={label}>
                <small>{t(label)}</small>
                <strong className="numeric">{value}</strong>
              </div>
            ))}
          </div>
        )}
        <footer className="original-footer">
          {!manolo && theme.footer && <p>{theme.footer}</p>}
          <div className="footer-columns">
            <span className="footer-issuer">
              {manolo ? (
                t('Vystavil') + ': Dominika Vašek'
              ) : edit || invoice.issuedBy ? (
                <>
                  <span>{t('Vystavil') + ':'}</span>
                  <span className="footer-issued-by">
                    {edit && (
                      <span className="footer-field-size" aria-hidden="true">
                        {invoice.issuedBy || t('Vystavil')}
                      </span>
                    )}
                    {field('issuedBy', 'Vystavil')}
                  </span>
                </>
              ) : null}
            </span>
            <span className="footer-contacts">
              {(manolo
                ? manoloBay.contacts.slice(1)
                : [invoice.supplier.website, invoice.supplier.email, invoice.supplier.phone]
              )
                .filter(Boolean)
                .map((contact, index) => (
                  <span key={index}>{contact}</span>
                ))}
            </span>
            <span className="footer-brand">
              <img src="/brand/invoy-wordmark.svg" alt="INVOY." />
              <small>www.invoy.xyz</small>
            </span>
          </div>
          {!mono && (theme.logo || invoice.logo) && (
            <img src={theme.logo || invoice.logo} alt="Logo dodávateľa" />
          )}
        </footer>
        {edit &&
          itemMenu &&
          menuItem &&
          createPortal(
            <div
              ref={menuRef}
              className="invoice-item-context-menu"
              role="dialog"
              aria-label="Možnosti položky"
              style={{
                left: Math.max(8, Math.min(itemMenu.x, window.innerWidth - 236)),
                top: Math.max(8, Math.min(itemMenu.y, window.innerHeight - 180)),
              }}
            >
              {(
                ['discount', ...(invoice.supplier.vatPayer ? ['vatRate'] : [])] as (
                  'discount' | 'vatRate'
                )[]
              ).map((key) => (
                <label key={key}>
                  {key === 'discount' ? 'Zľava %' : 'DPH %'}
                  <input
                    aria-label={key === 'discount' ? 'Zľava %' : 'DPH %'}
                    inputMode="decimal"
                    value={menuItem[key]}
                    onChange={(event) =>
                      edit.update({
                        items: invoice.items.map((item) =>
                          item.id === menuItem.id
                            ? { ...item, [key]: event.target.value.replace(',', '.') }
                            : item,
                        ),
                      })
                    }
                  />
                </label>
              ))}
              <button
                disabled={invoice.items.length === 1}
                onClick={() => {
                  edit.update({ items: invoice.items.filter((item) => item.id !== menuItem.id) });
                  setItemMenu(null);
                }}
              >
                <Trash2 size={13} /> Odstrániť položku
              </button>
            </div>,
            document.body,
          )}
      </article>
    </A4Paper>
  );
}
