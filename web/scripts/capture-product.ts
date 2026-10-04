// Capture the real application using only the isolated, synthetic product fixture.
// Run after building the web client; this script never accepts a URL or login details.
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { chromium, type Browser, type Page } from 'playwright';
import sharp from 'sharp';

const webDirectory = fileURLToPath(new URL('../', import.meta.url));
const outputDirectory = new URL('../src/assets/product/', import.meta.url);
const viewport = { width: 1328, height: 747 };
const deviceScaleFactor = 3;
let fixture: ChildProcess | undefined;
let browser: Browser | undefined;
let cleanupPromise: Promise<void> | undefined;

function startFixture(): Promise<URL> {
  fixture = spawn(
    process.execPath,
    ['--import', 'tsx', 'scripts/preview.ts', '--product', '--port=0'],
    {
      cwd: webDirectory,
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  const child = fixture;
  return new Promise((resolve, reject) => {
    let output = '';
    let settled = false;
    const timeout = setTimeout(
      () => finish(new Error('Product fixture did not start within 45s.')),
      45_000,
    );
    const finish = (error?: Error, url?: URL) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (error) reject(error);
      else resolve(url!);
    };
    child.on('error', (error) => finish(error));
    child.on('exit', (code, signal) => {
      finish(new Error(`Product fixture exited before startup (${code ?? signal}).\n${output}`));
    });
    child.stderr?.on('data', (chunk: Buffer) => {
      output = (output + chunk.toString()).slice(-8_000);
    });
    child.stdout?.on('data', (chunk: Buffer) => {
      output = (output + chunk.toString()).slice(-8_000);
      const match = output.match(/Synthetic local preview: (http:\/\/127\.0\.0\.1:\d+\/[^\s]*)/);
      if (!match) return;
      const url = new URL(match[1]);
      if (url.port === '0' || url.pathname !== '/__preview/login') {
        finish(new Error('Product fixture returned an unexpected preview URL.'));
        return;
      }
      finish(undefined, url);
    });
  });
}

async function stopFixture(child: ChildProcess): Promise<void> {
  if (!child.pid || child.exitCode !== null || child.signalCode !== null) return;
  await new Promise<void>((resolve) => {
    const timeout = setTimeout(() => child.kill('SIGKILL'), 5_000);
    child.once('exit', () => {
      clearTimeout(timeout);
      resolve();
    });
    child.kill('SIGINT');
  });
}

function cleanup(): Promise<void> {
  cleanupPromise ??= (async () => {
    try {
      await browser?.close();
    } finally {
      if (fixture) await stopFixture(fixture);
    }
  })();
  return cleanupPromise;
}

async function waitForPaint(page: Page): Promise<void> {
  await page.waitForFunction(
    () =>
      document.fonts.status === 'loaded' && [...document.images].every((image) => image.complete),
  );
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all(
      [...document.images].map((image) => {
        if (image.complete) {
          if (!image.naturalWidth) throw new Error(`Image failed to load: ${image.currentSrc}`);
          return;
        }
        return image.decode();
      }),
    );
    await new Promise<void>((resolve) =>
      requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
    );
  });
}

async function capture(page: Page, name: 'invoice' | 'overview'): Promise<void> {
  await waitForPaint(page);
  // Leave the pointer outside the controls without changing application markup or styling.
  await page.mouse.move(0, 0);
  const screenshot = await page.screenshot({ type: 'png', fullPage: false, scale: 'device' });
  const metadata = await sharp(screenshot).metadata();
  const width = viewport.width * deviceScaleFactor;
  const height = viewport.height * deviceScaleFactor;
  if (metadata.width !== width || metadata.height !== height) {
    throw new Error(
      `Unexpected ${name} screenshot size: ${metadata.width}×${metadata.height}; expected ${width}×${height}.`,
    );
  }
  await mkdir(outputDirectory, { recursive: true });
  for (const scale of [1, 2, 3]) {
    const filename = `${name}${scale === 1 ? '' : `@${scale}x`}.webp`;
    const image = await sharp(screenshot)
      .resize(viewport.width * scale, viewport.height * scale)
      .webp({ lossless: true })
      .toBuffer();
    await writeFile(new URL(filename, outputDirectory), image);
    console.log(
      `${filename}: ${viewport.width * scale}×${viewport.height * scale}, ${Math.round(image.length / 1024)} KB (lossless)`,
    );
  }
}

async function main(): Promise<void> {
  if (process.argv.length > 2)
    throw new Error('Product capture accepts no URLs, credentials or arguments.');
  const login = await startFixture();
  browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor,
    locale: 'sk-SK',
    timezoneId: 'Europe/Bratislava',
    colorScheme: 'light',
    reducedMotion: 'reduce',
    serviceWorkers: 'block',
  });
  const blockedRequests: string[] = [];
  await context.route('**/*', (route) => {
    const url = new URL(route.request().url());
    if (url.origin === login.origin) return route.continue();
    blockedRequests.push(`${url.protocol}//${url.host}${url.pathname}`);
    return route.abort('blockedbyclient');
  });
  const page = await context.newPage();
  page.setDefaultTimeout(15_000);
  page.setDefaultNavigationTimeout(30_000);
  await page.clock.setFixedTime(new Date('2026-10-04T10:00:00+02:00'));
  await page.goto(login.href, { waitUntil: 'networkidle' });
  await page
    .locator('.native-invoice-row')
    .filter({ hasText: '2026003' })
    .getByRole('button')
    .click();
  await page.getByRole('article', { name: 'Upraviteľná faktúra' }).waitFor({ state: 'visible' });
  await page.waitForFunction(() => {
    const frame = document.querySelector<HTMLElement>('.invoice-a4-frame');
    const paper = frame?.querySelector<HTMLElement>('.invoice-paper');
    return frame && paper && Math.abs(paper.getBoundingClientRect().width - frame.clientWidth) < 2;
  });
  await page.locator('.invoice-paper.manoloBay .manolo-logo').waitFor({ state: 'visible' });
  await capture(page, 'invoice');
  await page.getByRole('button', { name: 'Tabuľkový zoznam', exact: true }).click();
  await page.locator('.native-invoice-table tbody tr').nth(2).waitFor({ state: 'visible' });
  await capture(page, 'overview');
  if (blockedRequests.length) {
    throw new Error(
      `Capture attempted requests outside its isolated fixture: ${blockedRequests.join(', ')}`,
    );
  }
  console.log('Product previews refreshed from the current application and synthetic fixture.');
}

for (const [signal, code] of [
  ['SIGINT', 130],
  ['SIGTERM', 143],
] as const) {
  process.once(signal, () => {
    void cleanup().finally(() => process.exit(code));
  });
}

try {
  await main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
} finally {
  await cleanup();
}
