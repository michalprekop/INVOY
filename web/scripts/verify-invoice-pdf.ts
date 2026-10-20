// Browser regression checks with an isolated in-memory account and synthetic images.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { build } from 'esbuild';
import { chromium } from 'playwright';
import sharp from 'sharp';
import type { SavedInvoice } from '../shared/model';

const output = '../output/pdf-layout-qa';
await mkdir(output, { recursive: true });
const fixture = spawn(
  process.execPath,
  ['--import', 'tsx', 'scripts/preview.ts', '--template=manolo-bay', '--port=0'],
  { stdio: ['ignore', 'pipe', 'pipe'] },
);
const browser = await chromium.launch();
try {
  const url = await new Promise<string>((resolve, reject) => {
    const timer = setTimeout(() => reject(Error('PDF fixture did not start')), 30_000);
    let text = '';
    fixture.stdout.on('data', (chunk) => {
      text += String(chunk);
      const match = text.match(
        /Synthetic local preview: (http:\/\/127\.0\.0\.1:\d+\/__preview\/login)/,
      );
      if (match) {
        clearTimeout(timer);
        resolve(match[1]);
      }
    });
    fixture.once('error', reject);
    fixture.once('exit', (code) => {
      clearTimeout(timer);
      reject(Error(`PDF fixture exited: ${code}`));
    });
  });
  const bundle = await build({
    stdin: {
      contents:
        "import {renderInvoicePDF,renderInvoiceThumbnail} from './src/InvoicePDF';globalThis.qaPDF=renderInvoicePDF;globalThis.qaThumbnail=renderInvoiceThumbnail",
      resolveDir: process.cwd(),
      loader: 'tsx',
    },
    bundle: true,
    write: false,
    format: 'iife',
    platform: 'browser',
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, bypassCSP: true });
  await page.goto(url);
  await page.getByRole('button', { name: 'Uložiť PDF', exact: true }).waitFor();
  await page.addScriptTag({ content: bundle.outputFiles[0].text });
  // tsx preserves nested function names through this identity helper.
  await page.addScriptTag({ content: 'globalThis.__name = (fn) => fn;' });
  const svg = await readFile('public/brand/invoy-wordmark.svg', 'utf8');
  const bounds = await page.evaluate((markup) => {
    const host = document.createElement('div');
    host.innerHTML = markup;
    document.body.appendChild(host);
    const svg = host.querySelector('svg')!;
    const box = svg.querySelector('path')!.getBBox(),
      viewport = svg.viewBox.baseVal;
    const fits =
      box.x >= viewport.x &&
      box.y >= viewport.y &&
      box.x + box.width <= viewport.x + viewport.width &&
      box.y + box.height <= viewport.y + viewport.height;
    host.remove();
    return fits;
  }, svg);
  assert.ok(bounds, 'The complete wordmark, including its dot, must fit inside the SVG viewport');
  for (const layout of ['classic', 'mono', 'manoloBay'] as const) {
    for (const language of ['sk', 'en'] as const) {
      for (const long of [false, true]) {
        const result = await page.evaluate(
          async ({ layout, language, long }) => {
            const list = (await fetch('/api/invoices').then((r) => r.json())) as {
              items: { id: string }[];
            };
            const invoice = (await fetch('/api/invoices/' + list.items[0].id).then((r) =>
              r.json(),
            )) as SavedInvoice;
            const image = (width: number, height: number, header = false) => {
              const canvas = document.createElement('canvas');
              canvas.width = width;
              canvas.height = height;
              const c = canvas.getContext('2d')!;
              c.fillStyle = 'white';
              c.fillRect(0, 0, width, height);
              if (header) {
                c.fillStyle = 'black';
                c.font = 'bold 130px Arial';
                c.fillText('SAMPLE STUDIO', 0, 130);
              } else {
                c.strokeStyle = '#208060';
                c.lineWidth = 8;
                c.strokeRect(5, 5, width - 10, height - 10);
                c.strokeStyle = '#b020c0';
                c.beginPath();
                c.arc(80, height / 2, 55, 0, Math.PI * 2);
                c.stroke();
                c.fillStyle = '#208060';
                c.font = '30px Arial';
                c.fillText('SAMPLE SIGNATURE', 150, height / 2);
              }
              return canvas.toDataURL();
            };
            invoice.templateSnapshot = {
              ...invoice.templateSnapshot,
              layout,
              logo: image(1100, 160, true),
              wordmark: '',
              footer: '',
            };
            invoice.language = language;
            invoice.signature = image(480, 320);
            invoice.items = Array.from({ length: long ? 40 : 1 }, (_, index) => ({
              ...invoice.items[0],
              id: crypto.randomUUID(),
              name: `Správa a technická podpora webstránky\nSample.com, položka ${index + 1}`,
              unitPrice: '995',
            }));
            invoice.paid = String(995 * invoice.items.length);
            invoice.supplier.registration =
              'Okresný úrad Vzorové Mesto, Číslo živnostenského registra: 123–456';
            invoice.supplier.website = 'sample.test';
            invoice.supplier.email = 'studio@example.test';
            invoice.customer.vatID = 'CZ0123456789';
            invoice.note = 'Nie sme platiteľmi DPH.';
            const before = JSON.stringify(invoice);
            const blob: Blob = await (globalThis as any).qaPDF(invoice);
            const pdf = Array.from(new Uint8Array(await blob.arrayBuffer()));
            const pages = (await blob.text()).match(/\/Type\s*\/Page\b/g)?.length ?? 0;
            const thumbnail: string | null = long
              ? null
              : await (globalThis as any).qaThumbnail(invoice);
            if (JSON.stringify(invoice) !== before) throw Error('Export changed invoice data');
            return { pages, pdf, thumbnail };
          },
          { layout, language, long },
        );
        const name = `${layout}-${language}-${long ? 'long' : 'short'}`;
        if (long) assert.ok(result.pages > 1, `${name}: long invoices must paginate`);
        else
          assert.equal(result.pages, 1, `${name}: the complete short invoice must fit on one A4`);
        await writeFile(`${output}/${name}.pdf`, new Uint8Array(result.pdf));
        if (result.thumbnail) {
          const image = Buffer.from(result.thumbnail.split(',')[1], 'base64');
          await writeFile(`${output}/${name}.png`, image);
          const { data, info } = await sharp(image)
            .ensureAlpha()
            .raw()
            .toBuffer({ resolveWithObject: true });
          let minX = Infinity,
            maxX = -Infinity,
            minY = Infinity,
            maxY = -Infinity,
            pixels = 0;
          for (let y = 0; y < info.height; y++)
            for (let x = 0; x < info.width; x++) {
              const offset = (y * info.width + x) * 4;
              if (data[offset] > 110 && data[offset + 1] < 100 && data[offset + 2] > 110) {
                minX = Math.min(minX, x);
                maxX = Math.max(maxX, x);
                minY = Math.min(minY, y);
                maxY = Math.max(maxY, y);
                pixels++;
              }
            }
          assert.ok(pixels > 15, `${name}: signature must remain visible`);
          assert.ok(
            Math.abs((maxX - minX + 1) / (maxY - minY + 1) - 1) < 0.1,
            `${name}: a circle in the signature must remain circular`,
          );
        }
        console.log(`Verified ${name}: ${result.pages} page(s)`);
      }
    }
  }
} finally {
  await browser.close();
  fixture.kill('SIGINT');
}
