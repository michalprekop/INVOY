import { appleLoginPath } from '../shared/navigation';
import { useState } from 'react';
import { ProductPreview } from './ProductPreview';
import { ArrowDown, ArrowRight, ArrowUpRight, Check, FileText, List, Monitor } from 'lucide-react';
import { ErrorBox } from './ui';
import './landing.css';

import type { LandingConfig } from './Landing';

function AccountAction({ ready }: { ready: boolean }) {
  return (
    <div className="home-account">
      {ready ? (
        <a
          className="home-button home-button-primary"
          href={appleLoginPath(location.pathname)}
          aria-label="Vytvoriť účet / Prihlásiť sa cez Apple"
        >
          Vytvoriť účet / Prihlásiť sa
          <span className="home-apple-icon" aria-hidden="true">
            <img src="/brand/apple-logo-white.png" alt="" width="40" height="40" />
          </span>
        </a>
      ) : (
        <button className="home-button home-button-primary" disabled>
          Prihlásenie pripravujeme
        </button>
      )}
    </div>
  );
}

export function LandingA({ config, error }: { config: LandingConfig | null; error: string }) {
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
    <div className="home" id="top">
      <a className="home-skip" href="#obsah">
        Preskočiť na obsah
      </a>
      <header className="home-header home-width">
        <a className="home-wordmark" href="#top" aria-label="INVOY — úvod">
          INVOY<span>.</span>
        </a>
        <nav className="home-nav" aria-label="Hlavná navigácia">
          <a href="#produkt">Produkt</a>
          <a href="#ako-to-funguje">Ako to funguje</a>
          <a href="#web-a-mac">Web a Mac</a>
        </nav>
        <div className="home-header-actions">
          {ready && (
            <a className="home-login" href={appleLoginPath(location.pathname)}>
              Prihlásiť sa <ArrowUpRight size={15} aria-hidden="true" />
            </a>
          )}
          {config?.macAvailable && (
            <a className="home-button home-button-outline home-download" href="/download/mac">
              Pre Mac <ArrowDown size={15} aria-hidden="true" />
            </a>
          )}
        </div>
      </header>

      <main id="obsah">
        <section className="home-hero home-width" aria-labelledby="home-title">
          <div className="home-eyebrow">
            <span /> Menej administratívy. Viac vašej práce.
          </div>
          <div className="home-hero-grid">
            <h1 id="home-title">
              Faktúry, ktoré
              <br />
              robia dobrý
              <br />
              dojem.
            </h1>
            <div className="home-hero-aside">
              <p>
                Od dobre odvedenej práce
                <br className="home-desktop-break" /> k profesionálnej faktúre.
              </p>
              <p className="home-hero-description">
                Vlastný štýl, prehľad v úhradách a všetko na jednom mieste. Na webe aj na Macu.
              </p>
              <ErrorBox error={error || (auth ? (messages[auth] ?? '') : '')} />
              <AccountAction ready={ready} />
            </div>
          </div>
        </section>

        <section
          className="home-product home-width"
          id="produkt"
          aria-label="Náhľad aplikácie INVOY"
        >
          <div className="home-preview-controls" role="group" aria-label="Vybrať náhľad aplikácie">
            <button
              aria-pressed={preview === 'invoice'}
              onClick={() => setPreview('invoice')}
              aria-controls="home-preview"
            >
              <FileText size={15} aria-hidden="true" /> Faktúra
            </button>
            <button
              aria-pressed={preview === 'overview'}
              onClick={() => setPreview('overview')}
              aria-controls="home-preview"
            >
              <List size={16} aria-hidden="true" /> Prehľad
            </button>
          </div>
          <div className="home-preview-frame" id="home-preview">
            <div className="home-window-bar" aria-hidden="true">
              <div className="home-window-dots">
                <i />
                <i />
                <i />
              </div>
              <span>invoy.xyz</span>
              <span className="home-window-label">Váš pracovný priestor</span>
            </div>
            <ProductPreview preview={preview} className="home-product-image" eager />
          </div>
          <div className="home-preview-caption">
            <span>Skutočné rozhranie. Ukážkové údaje.</span>
            <span>
              <Check size={14} aria-hidden="true" /> Automatické ukladanie
            </span>
          </div>
        </section>

        <section className="home-features home-width" aria-labelledby="home-features-title">
          <div className="home-section-heading">
            <span className="home-kicker">PRE VAŠU KAŽDODENNÚ PRÁCU</span>
            <h2 id="home-features-title">
              Od prvého riadku
              <br />
              po posledný detail.
            </h2>
          </div>
          <div className="home-feature-grid">
            <article>
              <span className="home-feature-number">01 /</span>
              <h3>Faktúra s vaším podpisom.</h3>
              <p>
                Logo, firemné údaje a pridelené šablóny. Faktúra, ktorá patrí k vašej práci a vašej
                značke.
              </p>
            </article>
            <article>
              <span className="home-feature-number">02 /</span>
              <h3>Poriadok bez hľadania.</h3>
              <p>
                Odberatelia, splatnosti a úhrady v jednom prehľade. Existujúcu faktúru jednoducho
                nájdete alebo duplikujete.
              </p>
            </article>
            <article>
              <span className="home-feature-number">03 /</span>
              <h3>Pripravené na odovzdanie.</h3>
              <p>
                Prehľadné PDF s platobným QR kódom. Stiahnite ho a pošlite klientovi tak, ako ste
                zvyknutí.
              </p>
            </article>
          </div>
        </section>

        <section
          className="home-workflow home-width"
          id="ako-to-funguje"
          aria-labelledby="home-workflow-title"
        >
          <div className="home-section-heading">
            <span className="home-kicker">AKO TO FUNGUJE</span>
            <h2 id="home-workflow-title">
              Jasný postup.
              <br />
              Od začiatku.
            </h2>
            <p>Pracovný priestor, v ktorom sa rýchlo zorientujete.</p>
          </div>
          <ol className="home-steps">
            <li>
              <span>01</span>
              <div>
                <h3>Vytvorte si účet.</h3>
                <p>Prihláste sa cez Apple. Správca vám aktivuje účet a pridelí šablóny faktúr.</p>
              </div>
              <ArrowUpRight size={20} aria-hidden="true" />
            </li>
            <li>
              <span>02</span>
              <div>
                <h3>Doplňte to podstatné.</h3>
                <p>
                  Vyplňte firemné údaje, bankový účet a odberateľa. Pri ďalšej faktúre ich máte
                  poruke.
                </p>
              </div>
            </li>
            <li>
              <span>03</span>
              <div>
                <h3>Vystavte. Stiahnite. Hotovo.</h3>
                <p>
                  Upravte položky priamo vo faktúre a stiahnite PDF. Zmeny sa ukladajú automaticky.
                </p>
              </div>
            </li>
          </ol>
        </section>

        <section className="home-platform" id="web-a-mac" aria-labelledby="home-platform-title">
          <div className="home-platform-inner home-width">
            <div className="home-section-heading">
              <span className="home-kicker">
                <Monitor size={15} aria-hidden="true" /> WEB + MAC
              </span>
              <h2 id="home-platform-title">
                Jeden účet.
                <br />
                Všade vaša práca.
              </h2>
            </div>
            <div className="home-platform-copy">
              <p>
                Začnite v prehliadači alebo si stiahnite aplikáciu pre Mac. Faktúry a nastavenia
                máte v rovnakom cloudovom účte.
              </p>
              <div className="home-platform-points">
                <span>
                  <Check size={15} aria-hidden="true" /> Vlastný priestor pre vaše údaje
                </span>
                <span>
                  <Check size={15} aria-hidden="true" /> Denné cloudové zálohy
                </span>
                <span>
                  <Check size={15} aria-hidden="true" /> Export dát kedykoľvek
                </span>
              </div>
              {config?.macAvailable && (
                <a className="home-inline-link" href="/download/mac">
                  Stiahnuť INVOY pre Mac <ArrowDown size={17} aria-hidden="true" />
                </a>
              )}
            </div>
          </div>
        </section>

        <section className="home-end home-width" aria-labelledby="home-end-title">
          <div>
            <span className="home-kicker">INVOY</span>
            <h2 id="home-end-title">
              Dajte svojej práci
              <br />
              dobrú bodku.
            </h2>
          </div>
          <div>
            <AccountAction ready={ready} />
            <p className="home-activation-note">Nové účty aktivuje správca.</p>
          </div>
        </section>
      </main>

      <footer className="home-footer home-width">
        <a className="home-wordmark" href="#top" aria-label="INVOY — späť hore">
          INVOY<span>.</span>
        </a>
        <span>Váš priestor na faktúry.</span>
        <a href="/privacy.html">
          Ochrana údajov <ArrowUpRight size={14} aria-hidden="true" />
        </a>
        <a href="#top">
          Späť hore <ArrowRight className="home-up-arrow" size={15} aria-hidden="true" />
        </a>
      </footer>
    </div>
  );
}
