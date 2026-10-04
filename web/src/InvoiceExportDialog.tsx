import { useEffect, useRef, useState } from 'react';
import { Download } from 'lucide-react';
import type { InvoiceSummary } from '../shared/model';
import { BrandSelect } from './BrandSelect';
import { ErrorBox, Field, Modal } from './ui';
import { choosePDFDestination, savePDF } from './pdf-download';
import {
  exportSnapshots,
  exportYears,
  loadExportInvoices,
  selectExportInvoices,
} from './invoice-export';

export function InvoiceExportDialog({
  initialYear,
  onClose,
}: {
  initialYear: string;
  onClose: () => void;
}) {
  const [rows, setRows] = useState<InvoiceSummary[]>([]);
  const [year, setYear] = useState(initialYear);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState('');
  const [error, setError] = useState('');
  const active = useRef<AbortController | null>(null);
  useEffect(() => {
    const controller = new AbortController();
    active.current = controller;
    void loadExportInvoices(controller.signal)
      .then((invoices) => {
        if (controller.signal.aborted) return;
        setRows(invoices);
        const years = exportYears(invoices);
        setYear(years.includes(initialYear) ? initialYear : (years[0] ?? ''));
      })
      .catch((e: Error) => {
        if (!controller.signal.aborted) setError(e.message);
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => {
      active.current?.abort();
    };
  }, [initialYear]);
  const selected = selectExportInvoices(rows, year);
  async function download() {
    if (busy || loading || !selected.length) return;
    const controller = new AbortController();
    active.current = controller;
    setBusy(true);
    setError('');
    setProgress('Načítavam faktúry…');
    const filename = `Faktury-${year || 'vsetky-roky'}.pdf`;
    try {
      const destination = await choosePDFDestination(filename);
      const current = await loadExportInvoices(controller.signal);
      setRows(current);
      const invoices = selectExportInvoices(current, year);
      if (!invoices.length) throw Error('Pre zvolené obdobie nie sú žiadne faktúry.');
      const { renderInvoicesPDF } = await import('./InvoicePDF');
      const blob = await renderInvoicesPDF(exportSnapshots(invoices, controller.signal), {
        title: `Faktúry – ${year || 'všetky roky'}`,
        signal: controller.signal,
        onProgress: (count) => setProgress(`Pripravujem PDF… ${count} / ${invoices.length}`),
      });
      controller.signal.throwIfAborted();
      await savePDF(blob, filename, destination);
      onClose();
    } catch (e) {
      if (!controller.signal.aborted && (e as Error).name !== 'AbortError')
        setError((e as Error).message);
    } finally {
      if (!controller.signal.aborted) {
        setBusy(false);
        setProgress('');
      }
    }
  }
  return (
    <Modal title="Exportovať faktúry" className="invoice-export-dialog" onClose={onClose}>
      <p>Faktúry podľa dátumu vystavenia. Každá začne na novej strane.</p>
      <Field label="Rok">
        <BrandSelect
          aria-label="Rok exportu"
          value={year}
          onValueChange={setYear}
          disabled={loading || busy}
        >
          <option value="">Všetky roky</option>
          {exportYears(rows).map((value) => (
            <option key={value} value={value}>
              {value}
            </option>
          ))}
        </BrandSelect>
      </Field>
      <p role="status" aria-live="polite">
        {loading
          ? 'Načítavam faktúry…'
          : busy
            ? progress
            : `Počet faktúr: ${selected.length} · jedno PDF`}
      </p>
      <ErrorBox error={error} />
      <div className="invoice-export-actions">
        <button className="button secondary" onClick={onClose}>
          Zrušiť
        </button>
        <button
          className="button"
          disabled={loading || busy || !selected.length}
          onClick={() => void download()}
        >
          <Download size={16} /> Export PDF
        </button>
      </div>
    </Modal>
  );
}
