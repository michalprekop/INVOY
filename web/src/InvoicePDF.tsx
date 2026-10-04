import { flushSync } from 'react-dom';
import { createRoot } from 'react-dom/client';
import html2canvas from 'html2canvas';
import { jsPDF } from 'jspdf';
import type { SavedInvoice } from '../shared/model';
import { InvoicePaper, paymentPayload } from './InvoicePaper';

function waitForQR(paper: HTMLElement, needed: boolean): Promise<void> {
  if (!needed || paper.querySelector('.qr-code')) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const finish = (error?: Error) => {
      observer.disconnect();
      clearTimeout(timeout);
      if (error) reject(error);
      else resolve();
    };
    const check = () => {
      const error = paper.querySelector('[role="alert"]')?.textContent;
      if (error) finish(Error(error));
      else if (paper.querySelector('.qr-code')) finish();
    };
    const observer = new MutationObserver(check);
    const timeout = setTimeout(
      () => finish(Error('Platobný QR kód sa nepodarilo pripraviť.')),
      15_000,
    );
    observer.observe(paper, { childList: true, subtree: true });
    check();
  });
}

const pageWidth = 800;
const pageHeight = (pageWidth * 297) / 210;

function paginate(source: HTMLElement, host: HTMLElement): HTMLElement[] {
  const pages: HTMLElement[] = [];
  const style = getComputedStyle(source);
  const top = parseFloat(style.paddingTop),
    bottom = parseFloat(style.paddingBottom);
  const left = parseFloat(style.paddingLeft),
    right = parseFloat(style.paddingRight);
  const originalFooter = source.querySelector<HTMLElement>('.original-footer')!;
  let content!: HTMLElement;
  let capacity = 0;
  function newPage() {
    const page = source.cloneNode(false) as HTMLElement;
    Object.assign(page.style, {
      width: `${pageWidth}px`,
      minWidth: `${pageWidth}px`,
      maxWidth: `${pageWidth}px`,
      height: `${pageHeight}px`,
      minHeight: '0',
      aspectRatio: 'auto',
      position: 'relative',
      display: 'block',
      overflow: 'hidden',
      margin: '0',
      zoom: '1',
      boxShadow: 'none',
    });
    host.appendChild(page);
    if (!pages.length) {
      const background = source
        .querySelector<HTMLElement>('.manolo-background')
        ?.cloneNode(true) as HTMLElement | undefined;
      if (background) {
        background.style.zIndex = '0';
        page.appendChild(background);
      }
    }
    const footer = originalFooter.cloneNode(true) as HTMLElement;
    Object.assign(footer.style, {
      position: 'absolute',
      bottom: `${bottom}px`,
      left: `${left}px`,
      right: `${right}px`,
      margin: '0',
      paddingTop: '0',
      zIndex: '1',
    });
    page.appendChild(footer);
    capacity = pageHeight - top - bottom - footer.getBoundingClientRect().height - 32;
    content = document.createElement('div');
    content.style.cssText = 'position:relative;z-index:1;display:flow-root';
    page.appendChild(content);
    pages.push(page);
  }
  const fits = () => content.getBoundingClientRect().height <= capacity + 0.5;
  // Extremely long notes/rows are split between text lines, never through a QR image.
  function splitTall(node: HTMLElement) {
    const origin = node.getBoundingClientRect().top;
    const height = node.getBoundingClientRect().height;
    const boxes: { top: number; bottom: number }[] = [];
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const range = document.createRange();
      range.selectNodeContents(walker.currentNode);
      for (const rect of Array.from(range.getClientRects())) {
        if (rect.height) boxes.push({ top: rect.top - origin, bottom: rect.bottom - origin });
      }
    }
    for (const img of node.querySelectorAll('img')) {
      const rect = img.getBoundingClientRect();
      boxes.push({ top: rect.top - origin, bottom: rect.bottom - origin });
    }
    node.remove();
    let offset = 0;
    while (offset < height - 0.5) {
      let end = Math.min(height, offset + capacity);
      const crossed = boxes.filter(
        (box) => box.top < end && box.bottom > end && box.top > offset + 1,
      );
      if (crossed.length) end = Math.min(...crossed.map((box) => box.top));
      const clip = document.createElement('div');
      clip.style.cssText = `height:${end - offset}px;overflow:hidden;position:relative`;
      const fragment = node.cloneNode(true) as HTMLElement;
      fragment.style.margin = '0';
      fragment.style.position = 'relative';
      fragment.style.top = `${-offset}px`;
      clip.appendChild(fragment);
      content.appendChild(clip);
      offset = end;
      if (offset < height - 0.5) newPage();
    }
  }
  function append(node: HTMLElement) {
    content.appendChild(node);
    if (fits()) return;
    node.remove();
    if (content.childElementCount) newPage();
    content.appendChild(node);
    if (!fits()) splitTall(node);
  }
  newPage();
  for (const original of Array.from(source.children) as HTMLElement[]) {
    if (original.matches('style, .manolo-background, .original-footer')) continue;
    if (original instanceof HTMLTableElement) {
      const rows = Array.from(original.tBodies[0].rows);
      let table: HTMLTableElement | undefined;
      let body: HTMLTableSectionElement;
      const startTable = () => {
        table = original.cloneNode(false) as HTMLTableElement;
        if (original.tHead) table.appendChild(original.tHead.cloneNode(true));
        body = document.createElement('tbody');
        table.appendChild(body);
        content.appendChild(table);
      };
      for (const originalRow of rows) {
        if (!table) startTable();
        const row = originalRow.cloneNode(true) as HTMLTableRowElement;
        body!.appendChild(row);
        if (!fits()) {
          row.remove();
          if (!body!.rows.length) table!.remove();
          if (content.childElementCount) newPage();
          startTable();
          body!.appendChild(row);
          if (!fits()) {
            splitTall(table!);
            table = undefined;
          }
        }
      }
    } else append(original.cloneNode(true) as HTMLElement);
  }
  return pages;
}

/** Share the final A4 layout between PDF export and template screenshots. */
async function withInvoicePages<T>(
  invoice: SavedInvoice,
  render: (pages: HTMLElement[]) => Promise<T>,
): Promise<T> {
  const host = document.createElement('div');
  host.className = 'pdf-export-host native-shell';
  host.setAttribute('aria-hidden', 'true');
  host.inert = true;
  host.style.cssText =
    'position:fixed;left:-10000px;top:0;width:800px;height:auto;display:block;overflow:visible;pointer-events:none';
  document.body.appendChild(host);
  const original = document.createElement('div');
  host.appendChild(original);
  const root = createRoot(original);
  try {
    flushSync(() =>
      root.render(<InvoicePaper invoice={invoice} theme={invoice.templateSnapshot} />),
    );
    const paper = original.querySelector<HTMLElement>('.invoice-paper')!;
    await waitForQR(paper, Boolean(paymentPayload(invoice)));
    await document.fonts.ready;
    await Promise.all(Array.from(paper.querySelectorAll('img')).map((image) => image.decode()));
    const pages = paginate(paper, host);
    return await render(pages);
  } finally {
    root.unmount();
    host.remove();
  }
}

function capturePage(page: HTMLElement, scale: number) {
  return html2canvas(page, {
    scale,
    backgroundColor: '#ffffff',
    logging: false,
    windowWidth: 1200,
  });
}

/** A crisp first-page screenshot using exactly the same layout as the final PDF. */
export function renderInvoiceThumbnail(invoice: SavedInvoice): Promise<string> {
  return withInvoicePages(invoice, async ([page]) => {
    const canvas = await capturePage(page, 1);
    try {
      return canvas.toDataURL('image/png');
    } finally {
      canvas.width = 0;
      canvas.height = 0;
    }
  });
}

/** Render the saved snapshot offscreen, with A4 pages and a footer on each page. */
export async function renderInvoicePDF(invoice: SavedInvoice): Promise<Blob> {
  return renderInvoicesPDF([invoice], {
    title: `Faktúra ${invoice.number}`,
    author: invoice.supplier.name,
  });
}

/** Reuse the single-invoice layout, appending every page to one document. */
export async function renderInvoicesPDF(
  invoices: Iterable<SavedInvoice> | AsyncIterable<SavedInvoice>,
  options: {
    title: string;
    author?: string;
    signal?: AbortSignal;
    onProgress?: (count: number) => void;
  },
): Promise<Blob> {
  const pdf = new jsPDF({ unit: 'mm', format: 'a4', compress: true });
  pdf.setProperties({ title: options.title, author: options.author ?? 'INVOY' });
  let pageCount = 0;
  let count = 0;
  for await (const invoice of invoices) {
    options.signal?.throwIfAborted();
    await withInvoicePages(invoice, async (pages) => {
      for (const page of pages) {
        options.signal?.throwIfAborted();
        const canvas = await capturePage(page, 2);
        try {
          options.signal?.throwIfAborted();
          if (pageCount++) pdf.addPage();
          pdf.addImage(canvas, 'PNG', 0, 0, 210, 297, undefined, 'FAST');
        } finally {
          canvas.width = 0;
          canvas.height = 0;
        }
      }
    });
    options.onProgress?.(++count);
    // Let the browser paint progress and handle cancellation between invoices.
    await new Promise<void>((resolve) => setTimeout(resolve, 0));
  }
  options.signal?.throwIfAborted();
  if (!pageCount) throw Error('Pre zvolené obdobie nie sú žiadne faktúry.');
  return pdf.output('blob');
}
