import { appleLoginPath } from '../shared/navigation';
import { useState } from 'react';
import { ProductPreview } from './ProductPreview';
import {
  ArrowDown,
  ArrowUpRight,
  Asterisk,
  Check,
  Cloud,
  FileText,
  List,
  Plus,
} from 'lucide-react';
import type { LandingConfig } from './Landing';
import { ErrorBox } from './ui';
import { BrandWordmark } from './BrandWordmark';
import './landing-b.css';

function AppleMark() {
  return (
    <span className="lb-apple" aria-hidden="true">
      <img src="/brand/apple-logo-white.png" alt="" width="40" height="40" />
    </span>
  );
}

function AccountAction({ ready }: { ready: boolean }) {
  return ready ? (
    <a
      className="lb-button lb-button-apple"
      href={appleLoginPath(location.pathname)}
      aria-label="Vytvoriť účet / Prihlásiť sa cez Apple"
    >
      <span className="lb-button-label">Vytvoriť účet / Prihlásiť sa</span>
      <AppleMark />
    </a>
  ) : (
    <button className="lb-button" disabled>
      Prihlásenie pripravujeme
    </button>
  );
}

// Decorative composition, containing only fictional companies and example amounts.
function InvoiceComposition() {
  return (
    <div className="lb-composition" aria-label="Ilustračná ukážka faktúry a prehľadu úhrad">
      <div className="lb-brand-tile" aria-hidden="true">
        <span>PRÁCA, KTORÁ JE VAŠA.</span>
        <Asterisk strokeWidth={1.4} />
        <strong>
          Do posledného
          <br />
          detailu.
        </strong>
        <span>ROVNAKO AKO VAŠE FAKTÚRY.</span>
      </div>

      <div className="lb-mini-list" aria-hidden="true">
        <div className="lb-card-label">
          <span>Vaši odberatelia</span>
          <Plus size={17} />
        </div>
        <div>
          <span className="lb-avatar">S</span>
          <p>
            Štúdio Sever<small>Všetko na jednom mieste</small>
          </p>
          <ArrowUpRight size={17} />
        </div>
        <div>
          <span className="lb-avatar lb-avatar-clay">A</span>
          <p>
            Ateliér Forma<small>Údaje vždy poruke</small>
          </p>
          <ArrowUpRight size={17} />
        </div>
      </div>

      <div className="lb-invoice" aria-hidden="true">
        <div className="lb-invoice-heading">
          <strong>
            forma<span>®</span>
          </strong>
          <span>NEZÁVISLÉ KREATÍVNE ŠTÚDIO</span>
        </div>
        <div className="lb-invoice-title">
          <span>FAKTÚRA</span>
          <strong>2026003</strong>
        </div>
        <div className="lb-invoice-parties">
          <div>
            <small>DODÁVATEĽ</small>
            <strong>Ateliér Forma</strong>
            <span>Bratislava, Slovensko</span>
          </div>
          <div>
            <small>ODBERATEĽ</small>
            <strong>Štúdio Sever</strong>
            <span>Žilina, Slovensko</span>
          </div>
        </div>
        <div className="lb-invoice-line">
          <span>Vizuálna identita</span>
          <span>1 ×</span>
          <strong>1 250,00 €</strong>
        </div>
        <div className="lb-invoice-line">
          <span>Grafické podklady</span>
          <span>1 ×</span>
          <strong>450,00 €</strong>
        </div>
        <div className="lb-invoice-total">
          <span>SPOLU NA ÚHRADU</span>
          <strong>1 700,00 €</strong>
        </div>
        <div className="lb-invoice-foot">
          <span>Ďakujeme za spoluprácu.</span>
          <span>Vytvorené s INVOY.</span>
        </div>
      </div>

      <div className="lb-blue-tile" aria-hidden="true">
        <span>VIAC PRIESTORU</span>
        <strong>
          na to,
          <br />
          čo vás
          <br />
          <em>baví.</em>
        </strong>
        <Asterisk strokeWidth={1.1} />
      </div>
      <div className="lb-payment-stack" aria-hidden="true">
        <div>
          <span className="lb-file-icon">
            <FileText size={23} strokeWidth={1.4} />
          </span>
          <p>
            Vizuálna identita<small>Faktúra 2026003</small>
          </p>
          <span className="lb-payment-amount">
            1 700,00 €<small>Na úhradu</small>
          </span>
        </div>
        <div>
          <span className="lb-file-icon">
            <FileText size={23} strokeWidth={1.4} />
          </span>
          <p>
            Webdizajn<small>Faktúra 2026002</small>
          </p>
          <span className="lb-payment-amount">
            2 400,00 €
            <small className="lb-is-paid">
              <Check size={11} /> Uhradená
            </small>
          </span>
        </div>
      </div>
      <div className="lb-saved" aria-hidden="true">
        <span>
          <Check size={17} />
        </span>
        <p>
          Uložené. Vybavené.<small>Vaše zmeny sa ukladajú automaticky.</small>
        </p>
        <Cloud size={23} strokeWidth={1.4} />
      </div>
    </div>
  );
}

export function LandingB({ config, error }: { config: LandingConfig | null; error: string }) {
  const [preview, setPreview] = useState<'invoice' | 'overview'>('invoice');
  const auth = new URLSearchParams(location.search).get('auth');
  const messages: Record<string, string> = {
    failed: 'Apple prihlásenie sa nepodarilo. Skúste to znova.',
    closed: 'Registrácia ešte nie je otvorená.',
    suspended: 'Tento účet je pozastavený.',
    'not-configured': 'Apple prihlásenie sa ešte pripravuje.',
  };
  const ready = Boolean(config?.appleReady);

  return (
    <div className="landing-b" id="top">
      <a className="lb-skip" href="#obsah">
        Preskočiť na obsah
      </a>
      <header className="lb-header">
        <a className="lb-wordmark" href="#top" aria-label="INVOY — úvod">
          <BrandWordmark />
        </a>
        <nav className="lb-nav" aria-label="Hlavná navigácia">
          <a href="#produkt">Produkt</a>
          <a href="#ako-to-funguje">Ako to funguje</a>
          <a href="#web-a-mac">Web a Mac</a>
        </nav>
        <div className="lb-header-actions">
          {config?.macAvailable && (
            <a className="lb-mac-link" href="/download/mac">
              Stiahnuť pre Mac <ArrowDown size={15} />
            </a>
          )}
          {ready && (
            <a
              className="lb-button lb-button-apple lb-login"
              href={appleLoginPath(location.pathname)}
              aria-label="Prihlásiť sa cez Apple"
            >
              <span className="lb-button-label">Prihlásiť sa</span>
              <AppleMark />
            </a>
          )}
        </div>
      </header>

      <main id="obsah">
        <section className="lb-hero" aria-labelledby="lb-title">
          <h1 id="lb-title">
            <span>Vaša práca má štýl.</span>
            <span>Vaše faktúry tiež.</span>
          </h1>
          <p>
            Jednoduchá fakturácia pre ľudí, ktorí tvoria.
            <br className="lb-desktop-break" /> Od prvého nápadu po poslednú uhradenú faktúru.
          </p>
          <div className="lb-hero-action">
            <ErrorBox error={error || (auth ? (messages[auth] ?? '') : '')} />
            <AccountAction ready={ready} />
          </div>
          <InvoiceComposition />
          <div className="lb-composition-caption">
            <span>VÁŠ ŠTÝL. VÁŠ PRACOVNÝ PRIESTOR.</span>
            <span>Ilustračná ukážka · ukážkové údaje</span>
          </div>
        </section>

        <section className="lb-intro lb-width" aria-labelledby="lb-intro-title">
          <div className="lb-section-top">
            <span className="lb-eyebrow">01 — MENEJ ADMINISTRATÍVY</span>
            <Asterisk size={42} strokeWidth={1.3} aria-hidden="true" />
          </div>
          <div className="lb-intro-heading">
            <h2 id="lb-intro-title">
              Vy robíte svoju prácu.
              <br />
              INVOY jej dá bodku.
            </h2>
            <p>
              Pre freelancerov, štúdiá a malé firmy. Všetko potrebné na vystavenie faktúry, bez
              zbytočností okolo.
            </p>
          </div>
          <div className="lb-features">
            <article>
              <span>01 /</span>
              <h3>Vaša značka na papieri.</h3>
              <p>
                Vlastné logo, firemné údaje a pridelené šablóny. Aj faktúra môže vyzerať ako súčasť
                vašej práce.
              </p>
            </article>
            <article>
              <span>02 /</span>
              <h3>Prehľad, ktorý má zmysel.</h3>
              <p>
                Odberatelia, splatnosti a úhrady spolu. Nájdite faktúru, duplikujte ju a pokračujte
                tam, kde ste skončili.
              </p>
            </article>
            <article>
              <span>03 /</span>
              <h3>Hotové na odovzdanie.</h3>
              <p>
                Stiahnite prehľadné PDF s platobným QR kódom. Klientovi ho pošlite tak, ako ste
                zvyknutí.
              </p>
            </article>
          </div>
        </section>

        <section className="lb-product" id="produkt" aria-labelledby="lb-product-title">
          <div className="lb-width">
            <span className="lb-eyebrow">02 — POZRITE SA DOVNÚTRA</span>
            <div className="lb-product-heading">
              <h2 id="lb-product-title">Všetko pekne pokope.</h2>
              <div
                className="lb-preview-controls"
                role="group"
                aria-label="Vybrať náhľad aplikácie"
              >
                <button
                  aria-pressed={preview === 'invoice'}
                  aria-controls="lb-preview"
                  onClick={() => setPreview('invoice')}
                >
                  <FileText size={16} /> Faktúra
                </button>
                <button
                  aria-pressed={preview === 'overview'}
                  aria-controls="lb-preview"
                  onClick={() => setPreview('overview')}
                >
                  <List size={17} /> Prehľad
                </button>
              </div>
            </div>
            <div className="lb-browser" id="lb-preview">
              <div className="lb-browser-bar" aria-hidden="true">
                <span>
                  <i />
                  <i />
                  <i />
                </span>
                <span>invoy.xyz</span>
                <Cloud size={15} />
              </div>
              <ProductPreview preview={preview} />
            </div>
            <p className="lb-product-caption">Skutočné rozhranie INVOY. Ukážkové údaje.</p>
          </div>
        </section>

        <section
          className="lb-workflow lb-width"
          id="ako-to-funguje"
          aria-labelledby="lb-workflow-title"
        >
          <div>
            <span className="lb-eyebrow">03 — ZAČNITE JEDNODUCHO</span>
            <h2 id="lb-workflow-title">
              Od prihlásenia
              <br />k prvej faktúre.
            </h2>
          </div>
          <ol>
            <li>
              <span>01</span>
              <div>
                <h3>Vytvorte si účet.</h3>
                <p>Prihláste sa cez Apple. Správca vám aktivuje účet a pridelí šablóny.</p>
              </div>
            </li>
            <li>
              <span>02</span>
              <div>
                <h3>Doplňte svoje údaje.</h3>
                <p>Firma, bankový účet, odberateľ. Pri ďalšej faktúre už máte všetko poruke.</p>
              </div>
            </li>
            <li>
              <span>03</span>
              <div>
                <h3>Vystavte. Stiahnite. Vybavené.</h3>
                <p>
                  Upravte položky priamo na faktúre a stiahnite PDF. Zmeny sa ukladajú automaticky.
                </p>
              </div>
            </li>
          </ol>
        </section>

        <section className="lb-platform" id="web-a-mac" aria-labelledby="lb-platform-title">
          <div className="lb-width lb-platform-grid">
            <div className="lb-platform-art" aria-hidden="true">
              <div className="lb-app-icon">
                <BrandWordmark />
              </div>
              <span>WEB + MAC</span>
            </div>
            <div>
              <span className="lb-eyebrow">04 — TAM, KDE PRACUJETE</span>
              <h2 id="lb-platform-title">
                Na webe.
                <br />
                Na Macu. Vaše.
              </h2>
              <p>
                Jeden účet a rovnaké faktúry. Otvorte prehliadač alebo aplikáciu pre Mac a
                pokračujte vo svojej práci.
              </p>
              {config?.macAvailable && (
                <a className="lb-text-link" href="/download/mac">
                  Stiahnuť pre Mac <ArrowDown size={18} />
                </a>
              )}
            </div>
          </div>
        </section>

        <section className="lb-end lb-width" aria-labelledby="lb-end-title">
          <span className="lb-eyebrow">VAŠA ĎALŠIA DOBRÁ BODKA.</span>
          <h2 id="lb-end-title">
            Urobte dojem.
            <br />
            Aj faktúrou.
          </h2>
          <AccountAction ready={ready} />
          <p>Nové účty aktivuje správca.</p>
        </section>
      </main>

      <footer className="lb-footer lb-width">
        <a className="lb-wordmark" href="#top" aria-label="INVOY — späť hore">
          <BrandWordmark />
        </a>
        <span>Faktúry s vaším rukopisom.</span>
        <a href="/privacy.html">
          Ochrana údajov <ArrowUpRight size={14} />
        </a>
        <a href="#top">
          Späť hore <ArrowUpRight size={14} />
        </a>
      </footer>
    </div>
  );
}
