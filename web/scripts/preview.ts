// Isolated UI fixture runner. Never imported by the deployed Worker.
// Uses in-memory D1/R2 and listens only on loopback; no real invoices or credentials.
import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { harness } from '../tests/harness';
const landingPreview = process.argv.includes('--landing');
const productPreview = process.argv.includes('--product');
const previewPort = process.argv.find((arg) => arg.startsWith('--port='))?.split('=')[1];
const server = createServer();
await new Promise<void>((resolve, reject) => {
  server.once('error', reject);
  server.listen(Number(previewPort ?? (landingPreview ? '8792' : '8791')), '127.0.0.1', resolve);
});
const address = server.address();
if (!address || typeof address === 'string') throw new Error('Preview port unavailable');
const origin = `http://127.0.0.1:${address.port}`,
  h = await harness(origin);
if (productPreview) {
  // Representative regular account, only in this isolated in-memory fixture.
  await h.db
    .prepare("UPDATE users SET role='user',name='Ukážkové štúdio' WHERE id=?")
    .bind(h.identities.owner.id)
    .run();
}
const previewTemplate = process.argv.find((arg) => arg.startsWith('--template='))?.split('=')[1];
if (previewTemplate) {
  const template = await h.db
    .prepare('SELECT id FROM templates WHERE id=?')
    .bind(previewTemplate)
    .first();
  if (!template) throw new Error('Unknown preview template');
  await h.db
    .prepare('INSERT OR IGNORE INTO template_grants VALUES(?,?)')
    .bind(h.identities.owner.id, previewTemplate)
    .run();
}
for (const [index, customer] of [
  'Kreatívne štúdio',
  'Architektúra & priestor',
  'Ateliér Sever',
].entries()) {
  const invoice = await h.invoice('owner', `202600${index + 1}`);
  if (productPreview) {
    invoice.issueDate = '2026-10-04';
    invoice.dueDate = '2026-10-18';
  }
  if (previewTemplate) invoice.templateID = previewTemplate;
  invoice.customer.name = customer;
  Object.assign(invoice.customer, {
    street: 'Ateliérová 8',
    postalCode: '811 01',
    city: 'Bratislava',
    companyID: '87654321',
    taxID: '2020654321',
  });
  Object.assign(invoice.supplier, { companyID: '12345678', taxID: '2020123456' });
  invoice.items[0].unitPrice = String([1250, 450, 780][index]);
  invoice.paid = index === 1 ? '450' : '0';
  await h.request('owner', `/api/invoices/${invoice.id}`, 'PUT', invoice);
}
server.on('request', async (req, res) => {
  if (req.headers.host !== new URL(origin).host) {
    res.writeHead(403);
    res.end();
    return;
  }
  const url = new URL(req.url ?? '/', origin);
  if (landingPreview && url.pathname === '/api/config') {
    // UI-only fixture. The real authentication endpoints remain unconfigured.
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(
      JSON.stringify({
        name: 'INVOY',
        appleReady: true,
        registrationOpen: true,
        macAvailable: true,
      }),
    );
    return;
  }
  if (url.pathname === '/__preview/login') {
    const who = url.searchParams.get('as') ?? 'owner',
      identity = h.identities[who];
    if (!identity) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(302, {
      'Set-Cookie': `faktury_session=${identity.token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=3600`,
      Location: '/',
    });
    res.end();
    return;
  }
  const headers = new Headers();
  for (const [key, value] of Object.entries(req.headers)) {
    if (value) headers.set(key, Array.isArray(value) ? value.join(',') : value);
  }
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(Buffer.from(chunk));
  try {
    const response = await h.mf.dispatchFetch(url.toString(), {
      method: req.method,
      redirect: 'manual',
      headers: Object.fromEntries(headers),
      body: ['GET', 'HEAD'].includes(req.method ?? 'GET') ? undefined : Buffer.concat(chunks),
    });
    res.writeHead(response.status, Object.fromEntries(response.headers));
    if (response.body) Readable.fromWeb(response.body as never).pipe(res);
    else res.end();
  } catch {
    res.writeHead(500);
    res.end('Preview request failed');
  }
});
console.log('Synthetic local preview: ' + origin + (landingPreview ? '/' : '/__preview/login'));
async function closePreview() {
  server.close();
  await h.mf.dispose();
  process.exit(0);
}
process.on('SIGINT', closePreview);
process.on('SIGTERM', closePreview);
