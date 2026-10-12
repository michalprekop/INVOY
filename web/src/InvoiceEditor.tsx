import { BrandSelect } from './BrandSelect';
import { useEffect, useRef, useState } from 'react';
import { Check, Copy, Download, History, Palette, Settings2, Trash2 } from 'lucide-react';
import {
  invoiceSchema,
  invoiceInput,
  baseConfig,
  totals,
  type SavedInvoice,
  type Invoice,
  type Profile,
  type Template,
} from '../shared/model';
import { api } from './api';
import { Field, ErrorBox, Modal, useUnsaved } from './ui';
import { InvoicePaper } from './InvoicePaper';
import { choosePDFDestination, pdfFilename, savePDF } from './pdf-download';

export function InvoiceEditor({
  initial,
  profile,
  templates,
  accountID,
  onSaved,
  onDuplicate,
  onDelete,
  registerFlush,
}: {
  initial: Invoice | SavedInvoice;
  profile: Profile;
  templates: Template[];
  accountID: string;
  onSaved: (invoice: SavedInvoice) => void;
  onDuplicate: (invoice: Invoice) => void;
  onDelete: () => void;
  registerFlush: (flush: (() => Promise<boolean>) | null) => void;
}) {
  const journal = `faktury-draft:${accountID}:${initial.id}`;
  const initialInput = 'templateSnapshot' in initial ? invoiceInput(initial) : initial;
  const [invoice, setInvoice] = useState<Invoice>(() => {
    try {
      const raw = localStorage.getItem(journal);
      if (raw) {
        const draft = JSON.parse(raw) as Invoice;
        if (draft.id === initial.id) return draft;
      }
    } catch {}
    return initialInput;
  });
  const [saved, setSaved] = useState<SavedInvoice | null>(
    'templateSnapshot' in initial ? initial : null,
  );
  const [error, setError] = useState(''),
    [busy, setBusy] = useState(false),
    [exporting, setExporting] = useState(false),
    [options, setOptions] = useState(false),
    [history, setHistory] = useState<{ version: number; created_at: string }[] | null>(null);
  const latest = useRef(invoice),
    ack = useRef(saved),
    inflight = useRef<Promise<boolean> | null>(null),
    mounted = useRef(true),
    blocked = useRef(false),
    exportingRef = useRef(false);
  latest.current = invoice;
  const dirty = !saved || JSON.stringify(invoice) !== JSON.stringify(invoiceInput(saved));
  const paid = Number(invoice.paid) >= Number(totals(invoice).total);
  const overdue = !paid && invoice.dueDate < new Date().toLocaleDateString('sv-SE');
  useUnsaved(dirty);
  const theme =
    saved?.templateID === invoice.templateID
      ? saved.templateSnapshot
      : (templates.find((t) => t.id === invoice.templateID)?.config ?? baseConfig);
  function update(change: Partial<Invoice>) {
    blocked.current = false;
    setError('');
    setInvoice((i) => ({ ...i, ...change }));
  }
  async function flush(): Promise<boolean> {
    if (inflight.current) return inflight.current;
    const work = (async () => {
      while (
        !ack.current ||
        JSON.stringify(latest.current) !== JSON.stringify(invoiceInput(ack.current))
      ) {
        const snapshot = latest.current,
          parsed = invoiceSchema.safeParse(snapshot);
        if (!parsed.success) {
          setError(
            parsed.error.issues
              .slice(0, 2)
              .map((i) => i.message)
              .join(' '),
          );
          return false;
        }
        setBusy(true);
        try {
          const next = await api<SavedInvoice>(`/invoices/${snapshot.id}`, {
            method: 'PUT',
            body: JSON.stringify(parsed.data),
          });
          ack.current = next;
          // A completed request must not replace characters typed while it was saving.
          latest.current =
            JSON.stringify(latest.current) === JSON.stringify(snapshot)
              ? invoiceInput(next)
              : { ...latest.current, version: next.version };
          if (mounted.current) {
            setSaved(next);
            setInvoice(latest.current);
          }
          onSaved(next);
          if (JSON.stringify(latest.current) === JSON.stringify(invoiceInput(next)))
            localStorage.removeItem(journal);
          else localStorage.setItem(journal, JSON.stringify(latest.current));
        } catch (e) {
          blocked.current = true;
          setError((e as Error).message);
          return false;
        }
      }
      setError('');
      return true;
    })();
    inflight.current = work;
    try {
      return await work;
    } finally {
      inflight.current = null;
      if (mounted.current) setBusy(false);
    }
  }
  useEffect(() => {
    mounted.current = true;
    registerFlush(flush);
    return () => {
      mounted.current = false;
      registerFlush(null);
    };
  }, []);
  useEffect(() => {
    if (!dirty) return;
    try {
      localStorage.setItem(journal, JSON.stringify(invoice));
    } catch {
      setError('Rozpracované údaje sa nepodarilo uložiť do prehliadača. Nezatvárajte stránku.');
    }
    if (blocked.current) return;
    const timer = setTimeout(() => void flush(), 450);
    return () => clearTimeout(timer);
  }, [invoice, dirty]);
  async function downloadPDF() {
    if (exportingRef.current) return;
    exportingRef.current = true;
    setExporting(true);
    try {
      if (!invoiceSchema.safeParse(latest.current).success) {
        await flush();
        return;
      }
      const filename = pdfFilename(latest.current.number);
      const destination = await choosePDFDestination(filename);
      if (!(await flush()) || !ack.current) return;
      const snapshot = structuredClone(ack.current);
      const { renderInvoicePDF } = await import('./InvoicePDF');
      await savePDF(await renderInvoicePDF(snapshot), filename, destination);
    } catch (e) {
      if ((e as Error).name !== 'AbortError') setError((e as Error).message);
    } finally {
      exportingRef.current = false;
      if (mounted.current) setExporting(false);
    }
  }
  return (
    <div className="original-editor" data-unsaved={dirty}>
      <div className="original-editor-toolbar">
        <b className="numeric">{invoice.number || 'Nová faktúra'}</b>
        <span className={'native-status' + (paid ? ' paid' : overdue ? ' overdue' : '')}>
          {paid ? 'Uhradená' : overdue ? 'Po splatnosti' : 'Na úhradu'}
        </span>
        {!paid && (
          <button
            className="button secondary"
            onClick={() => update({ paid: totals(invoice).total })}
          >
            <Check size={16} aria-hidden="true" /> Označiť ako uhradenú
          </button>
        )}
        <span className="save-state">{busy ? 'Ukladám…' : dirty ? 'Rozpracované' : 'Uložené'}</span>
        <div className="toolbar-actions">
          <BrandSelect
            aria-label="Šablóna faktúry"
            title="Šablóna faktúry"
            leadingIcon={<Palette size={16} aria-hidden="true" />}
            value={invoice.templateID}
            onValueChange={(value) => update({ templateID: value })}
          >
            {!templates.some((t) => t.id === invoice.templateID) && (
              <option value={invoice.templateID}>{saved?.templateName ?? 'Pôvodná šablóna'}</option>
            )}
            {templates.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
              </option>
            ))}
          </BrandSelect>
          <button
            title="Duplikovať"
            aria-label="Duplikovať"
            onClick={() => onDuplicate(latest.current)}
          >
            <Copy size={16} />
          </button>
          <button title="Vymazať" aria-label="Vymazať" onClick={onDelete}>
            <Trash2 size={16} />
          </button>
          <button
            title="Možnosti faktúry"
            aria-label="Možnosti faktúry"
            onClick={() => setOptions(true)}
          >
            <Settings2 size={16} />
          </button>
          <button
            className="button"
            title="Uložiť PDF"
            aria-label="Uložiť PDF"
            aria-busy={exporting}
            disabled={exporting}
            onClick={() => void downloadPDF()}
          >
            <Download size={15} /> {exporting ? 'PDF…' : 'PDF'}
          </button>
        </div>
      </div>
      <ErrorBox error={error} />
      {error && (
        <button
          className="retry-save"
          onClick={() => {
            blocked.current = false;
            void flush();
          }}
        >
          Zopakovať uloženie
        </button>
      )}
      <div className="original-paper-canvas">
        <InvoicePaper invoice={invoice} theme={theme} edit={{ update, profile }} />
      </div>
      {options && (
        <Modal title="Možnosti faktúry" onClose={() => setOptions(false)}>
          <div className="form-grid">
            <Field label="Konštantný symbol">
              <input
                value={invoice.constantSymbol}
                onChange={(e) => update({ constantSymbol: e.target.value })}
              />
            </Field>
            <Field label="Špecifický symbol">
              <input
                value={invoice.specificSymbol}
                onChange={(e) => update({ specificSymbol: e.target.value })}
              />
            </Field>
            <Field label="Objednávka">
              <input
                value={invoice.orderNumber ?? ''}
                onChange={(e) => update({ orderNumber: e.target.value })}
              />
            </Field>
            <Field label="Dátum dodania">
              <input
                type="date"
                value={invoice.deliveryDate ?? ''}
                onChange={(e) => update({ deliveryDate: e.target.value || null })}
              />
            </Field>
            <Field label="Platobný QR kód">
              <BrandSelect
                aria-label="Platobný QR kód"
                value={invoice.qrFormat}
                onValueChange={(value) => update({ qrFormat: value as Invoice['qrFormat'] })}
              >
                {[
                  ['automatic', 'Automaticky podľa odberateľa'],
                  ['payBySquare', 'PAY by square (Slovensko)'],
                  ['qrPlatba', 'QR Platba (Česko)'],
                  ['disabled', 'Bez QR kódu'],
                ].map(([v, l]) => (
                  <option key={v} value={v}>
                    {l}
                  </option>
                ))}
              </BrandSelect>
            </Field>
          </div>
          <button
            className="button secondary"
            onClick={async () => {
              try {
                setHistory(await api(`/invoices/${invoice.id}/versions`));
                setOptions(false);
              } catch (e) {
                setError((e as Error).message);
              }
            }}
          >
            <History size={15} /> História zmien
          </button>
        </Modal>
      )}
      {history && (
        <Modal title="História zmien" onClose={() => setHistory(null)}>
          {history.map((h) => (
            <button
              className="history-row"
              key={h.version}
              onClick={async () => {
                if (!confirm('Načítať túto verziu ako novú úpravu?')) return;
                const old = await api<SavedInvoice>(
                  `/invoices/${invoice.id}/versions/${h.version}`,
                );
                update({ ...invoiceInput(old), version: latest.current.version });
                setHistory(null);
              }}
            >
              Verzia {h.version} · {new Date(h.created_at).toLocaleString('sk-SK')}
            </button>
          ))}
        </Modal>
      )}
    </div>
  );
}
