import { BrandSelect } from './BrandSelect';
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowLeft,
  Building2,
  ChevronDown,
  FileText,
  LogOut,
  Monitor,
  PanelLeft,
  Plus,
  Search,
  Settings as SettingsIcon,
  ShieldCheck,
  Table2,
  Trash2,
  RotateCcw,
  MoreHorizontal,
} from 'lucide-react';
import { api } from './api';
import {
  freshInvoice,
  invoiceInput,
  money,
  displayDate,
  totals,
  emptyCompany,
  type Invoice,
  type SavedInvoice,
  type InvoiceSummary,
  type Profile,
  type Template,
  type User,
  type Company,
} from '../shared/model';
import { InvoiceEditor } from './InvoiceEditor';
import { InvoiceExportDialog } from './InvoiceExportDialog';
import { Settings } from './Settings';
import { Admin } from './Admin';
import { ErrorBox, Modal, CompanyFields } from './ui';
import './legacy.css';
import { BrandWordmark } from './BrandWordmark';
import { AppUpdateNotice } from './AppUpdateNotice';
import { ADMIN_PATH } from '../shared/navigation';

type Me = { user: User; profile: Profile; profileVersion: number };
export function LegacyWorkspace({
  me,
  templates,
  onProfile,
  onLogout,
}: {
  me: Me;
  templates: Template[];
  onProfile: (p: Profile, v: number) => void;
  onLogout: () => Promise<void>;
}) {
  const [page, setPage] = useState(
    location.pathname === ADMIN_PATH && me.user.role === 'admin' ? 'admin' : 'invoices',
  );
  const [rows, setRows] = useState<InvoiceSummary[]>([]),
    [editor, setEditor] = useState<Invoice | SavedInvoice | null>(null),
    [error, setError] = useState(''),
    [loading, setLoading] = useState(true);
  const [query, setQuery] = useState(''),
    [filter, setFilter] = useState('Všetky'),
    [year, setYear] = useState(''),
    [sort, setSort] = useState('Najnovšie'),
    [table, setTable] = useState(false),
    [trash, setTrash] = useState(false),
    [compactDetail, setCompactDetail] = useState(false);
  const [exporting, setExporting] = useState(false);
  const invoiceFlush = useRef<(() => Promise<boolean>) | null>(null),
    settingsFlush = useRef<(() => Promise<boolean>) | null>(null),
    openSequence = useRef(0),
    navigationSequence = useRef(0);
  const accountMenu = useRef<HTMLDetailsElement>(null);
  const accountName = me.user.name.trim() || me.user.email;
  useEffect(() => {
    function dismiss(event: PointerEvent) {
      if (!accountMenu.current?.contains(event.target as Node)) {
        accountMenu.current?.removeAttribute('open');
      }
    }
    function escape(event: KeyboardEvent) {
      if (event.key === 'Escape' && accountMenu.current?.open) {
        accountMenu.current.removeAttribute('open');
        accountMenu.current.querySelector('summary')?.focus();
      }
    }
    document.addEventListener('pointerdown', dismiss);
    document.addEventListener('keydown', escape);
    return () => {
      document.removeEventListener('pointerdown', dismiss);
      document.removeEventListener('keydown', escape);
    };
  }, []);
  const today = new Date().toLocaleDateString('sv-SE');
  const status = (i: InvoiceSummary) =>
    Number(i.paid) >= Number(i.total)
      ? 'Uhradené'
      : i.dueDate < today
        ? 'Po splatnosti'
        : 'Neuhradené';
  const sorted = useMemo(
    () =>
      [...rows].sort((a, b) =>
        sort === 'Odberateľ'
          ? a.customer.localeCompare(b.customer)
          : sort === 'Splatnosť'
            ? a.dueDate.localeCompare(b.dueDate)
            : (b.issueDate ?? b.updated_at).localeCompare(a.issueDate ?? a.updated_at) ||
              b.number.localeCompare(a.number),
      ),
    [rows, sort],
  );
  const visible = useMemo(
    () =>
      sorted.filter(
        (i) =>
          (i.number + ' ' + i.customer + ' ' + (i.searchText ?? ''))
            .toLocaleLowerCase('sk')
            .includes(query.toLocaleLowerCase('sk')) &&
          (!year || (i.issueDate ?? i.updated_at).startsWith(year)) &&
          (filter === 'Všetky' ||
            status(i) === filter ||
            (filter === 'Neuhradené' && status(i) !== 'Uhradené')),
      ),
    [sorted, query, year, filter, today],
  );
  async function load() {
    setLoading(true);
    try {
      let offset: number | null = 0,
        all: InvoiceSummary[] = [];
      do {
        const data: { items: InvoiceSummary[]; nextOffset: number | null } = await api<{
          items: InvoiceSummary[];
          nextOffset: number | null;
        }>(`/invoices?trash=${trash ? 1 : 0}&offset=${offset}`);
        all.push(...data.items);
        offset = data.nextOffset;
      } while (offset !== null);
      setRows(all);
      return all;
    } catch (e) {
      setError((e as Error).message);
      return [];
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    void load().then((all) => {
      if (!trash && all.length && !editor)
        void open(
          [...all].sort(
            (a, b) =>
              (b.issueDate ?? b.updated_at).localeCompare(a.issueDate ?? a.updated_at) ||
              b.number.localeCompare(a.number),
          )[0].id,
        );
    });
  }, [trash]);
  async function ready() {
    const flush = page === 'settings' ? settingsFlush : invoiceFlush;
    return !flush.current || (await flush.current());
  }
  async function open(id: string) {
    if (editor?.id === id) {
      setCompactDetail(true);
      setTable(false);
      return;
    }
    if (!(await ready())) return;
    const seq = ++openSequence.current;
    try {
      const invoice = await api<SavedInvoice>(`/invoices/${id}`);
      if (seq === openSequence.current) {
        setEditor(invoice);
        setCompactDetail(true);
        setTable(false);
        setError('');
      }
    } catch (e) {
      setError((e as Error).message);
    }
  }
  async function newInvoice(source?: Invoice | SavedInvoice) {
    if (!(await ready())) return;
    try {
      const t =
        templates.find((t) => t.id === (source?.templateID ?? me.profile.defaultTemplateID)) ??
        templates[0];
      if (!t) throw Error('Správca musí najprv priradiť šablónu.');
      const { number } = await api<{ number: string }>('/next-number');
      const fresh = freshInvoice(me.profile, number, t.id);
      setCompactDetail(true);
      setEditor(
        source
          ? {
              ...('templateSnapshot' in source ? invoiceInput(source) : source),
              id: fresh.id,
              version: 0,
              number,
              variableSymbol: fresh.variableSymbol,
              issueDate: fresh.issueDate,
              dueDate: fresh.dueDate,
              deliveryDate: null,
              paid: '0',
              nativeDates: undefined,
              templateID: t.id,
              items: source.items.map((i) => ({ ...i, id: crypto.randomUUID() })),
            }
          : fresh,
      );
      setPage('invoices');
      setTable(false);
      setQuery('');
      setFilter('Všetky');
      setYear('');
      setError('');
    } catch (e) {
      setError((e as Error).message);
    }
  }
  async function remove(i: InvoiceSummary | Invoice | SavedInvoice, restore = false) {
    if (!(await ready())) return;
    if (!restore && !confirm(`Vymazať faktúru ${i.number}?`)) return;
    try {
      // The editor may have just advanced its version during the flush.
      const current = await api<SavedInvoice>(`/invoices/${i.id}`);
      await api(`/invoices/${i.id}/trash`, {
        method: 'POST',
        body: JSON.stringify({ version: current.version, restore }),
      });
      if (editor?.id === i.id) setEditor(null);
      const all = await load();
      if (!trash && all.length) void open(all[0].id);
    } catch (e) {
      setError((e as Error).message);
    }
  }
  function saved(i: SavedInvoice) {
    const summary: InvoiceSummary = {
      id: i.id,
      number: i.number,
      version: i.version,
      updated_at: i.updatedAt,
      customer: i.customer.name,
      paid: i.paid,
      total: totals(i).total,
      currency: i.currency,
      dueDate: i.dueDate,
      issueDate: i.issueDate,
      searchText: JSON.stringify([i.items, i.note, i.customer]),
      deleted_at: null,
    };
    setRows((rows) =>
      rows.some((r) => r.id === i.id)
        ? rows.map((r) => (r.id === i.id ? summary : r))
        : [summary, ...rows],
    );
  }
  async function navigate(next: string) {
    const sequence = ++navigationSequence.current;
    if ((await ready()) && sequence === navigationSequence.current) {
      const path = next === 'admin' ? ADMIN_PATH : '/';
      if (location.pathname !== path) history.replaceState(null, '', path);
      setPage(next);
      setError('');
      accountMenu.current?.removeAttribute('open');
    }
  }
  return (
    <div className="native-shell">
      <header className="native-header">
        <div className="native-brand">
          <BrandWordmark />
        </div>
        <nav className="native-segments" aria-label="Hlavná navigácia">
          {[
            ['invoices', 'Faktúry', FileText],
            ['customers', 'Odberatelia', Building2],
            ...(me.user.role === 'admin' ? [['admin', 'Administrácia', ShieldCheck]] : []),
          ].map(([id, label, Icon]) => (
            <button
              key={String(id)}
              aria-pressed={page === id}
              className={page === id ? 'active' : ''}
              onClick={() => void navigate(String(id))}
            >
              {typeof Icon !== 'string' && <Icon size={15} />} {String(label)}
            </button>
          ))}
        </nav>
        <details className="account-menu" ref={accountMenu}>
          <summary aria-label={`Menu účtu: ${accountName}`} title={accountName}>
            <span>{accountName}</span>
            <ChevronDown size={12} aria-hidden="true" />
          </summary>
          <div>
            <button onClick={() => void navigate('settings')}>
              <SettingsIcon size={16} aria-hidden="true" />
              Nastavenia
            </button>
            <a href="/download/mac" onClick={() => accountMenu.current?.removeAttribute('open')}>
              <Monitor size={16} aria-hidden="true" />
              Mac appka
            </a>
            <hr />
            <button
              onClick={async () => {
                try {
                  if (await ready()) await onLogout();
                } catch (e) {
                  setError((e as Error).message);
                }
              }}
            >
              <LogOut size={16} aria-hidden="true" />
              Odhlásiť sa
            </button>
          </div>
        </details>
      </header>
      <ErrorBox error={error} />
      <div className="native-invoices" style={{ display: page === 'invoices' ? 'flex' : 'none' }}>
        <div className="native-overview native-invoice-toolbar">
          <div className="native-segments">
            {['Všetky', 'Uhradené', 'Neuhradené', 'Po splatnosti'].map((f) => (
              <button
                key={f}
                aria-pressed={filter === f}
                className={filter === f ? 'active' : ''}
                onClick={() => setFilter(f)}
              >
                {f}
              </button>
            ))}
          </div>
          <div className="native-invoice-summary">
            <strong>
              {rows.length} faktúr{trash ? ' v koši' : ''}
            </strong>
            {!trash && (
              <button
                className="invoice-export-link"
                disabled={loading || !rows.length}
                onClick={async () => {
                  if (await ready()) setExporting(true);
                }}
              >
                Exportovať
              </button>
            )}
          </div>
          <div className="native-invoice-actions">
            <label className="native-search">
              <Search size={15} />
              <input
                aria-label="Hľadať vo faktúrach"
                placeholder="Hľadať vo faktúrach"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
            </label>
            <button className="button" onClick={() => void newInvoice()}>
              <Plus size={16} /> Nová faktúra
            </button>
          </div>
          <button
            title={trash ? 'Späť na faktúry' : 'Kôš'}
            aria-label={trash ? 'Späť na faktúry' : 'Kôš'}
            onClick={async () => {
              if (await ready()) {
                setTrash(!trash);
                setEditor(null);
              }
            }}
          >
            {trash ? <RotateCcw size={15} /> : <Trash2 size={15} />}
          </button>
          <div className="native-segments">
            <button
              className={!table ? 'active' : ''}
              aria-label="Zoznam s náhľadom"
              title="Zoznam s náhľadom"
              onClick={async () => {
                if (await ready()) setTable(false);
              }}
            >
              <PanelLeft size={16} />
            </button>
            <button
              className={table ? 'active' : ''}
              aria-label="Tabuľkový zoznam"
              title="Tabuľkový zoznam"
              onClick={async () => {
                if (await ready()) setTable(true);
              }}
            >
              <Table2 size={16} />
            </button>
          </div>
        </div>
        <div
          className={
            'native-split' + (compactDetail && !table && !trash && editor ? ' compact-detail' : '')
          }
        >
          <aside className={'native-invoice-list' + (table ? ' table-mode' : '')}>
            <div className="native-list-heading">
              <BrandSelect aria-label="Rok" value={year} onValueChange={(value) => setYear(value)}>
                <option value="">Všetky roky</option>
                {[...new Set(rows.map((i) => (i.issueDate ?? i.updated_at).slice(0, 4)))]
                  .sort()
                  .reverse()
                  .map((y) => (
                    <option key={y}>{y}</option>
                  ))}
              </BrandSelect>
              <BrandSelect
                aria-label="Zoradenie"
                value={sort}
                onValueChange={(value) => setSort(value)}
              >
                {['Najnovšie', 'Splatnosť', 'Odberateľ'].map((s) => (
                  <option key={s}>{s}</option>
                ))}
              </BrandSelect>
            </div>
            <div className="native-list-scroll">
              {table ? (
                <table className="native-invoice-table">
                  <thead>
                    <tr>
                      <th>Číslo</th>
                      <th>Odberateľ</th>
                      <th>Stav</th>
                      <th>Suma</th>
                      <th>Vystavenie / splatnosť</th>
                      {trash && <th>Obnova</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {visible.map((i) => (
                      <tr
                        key={i.id}
                        className={editor?.id === i.id ? 'selected' : ''}
                        onDoubleClick={() => !trash && void open(i.id)}
                      >
                        <td>
                          <button className="numeric" onClick={() => !trash && void open(i.id)}>
                            {i.number}
                          </button>
                        </td>
                        <td>{i.customer}</td>
                        <td>
                          <span
                            className={
                              'native-status ' +
                              (status(i) === 'Uhradené'
                                ? 'paid'
                                : status(i) === 'Po splatnosti'
                                  ? 'overdue'
                                  : 'unpaid')
                            }
                          >
                            {status(i) === 'Uhradené'
                              ? 'Uhradená'
                              : status(i) === 'Neuhradené'
                                ? 'Na úhradu'
                                : 'Po splatnosti'}
                          </span>
                        </td>
                        <td className="numeric">{money(i.total, i.currency)}</td>
                        <td className="numeric">
                          {displayDate(i.issueDate ?? i.dueDate)}
                          <small>{displayDate(i.dueDate)}</small>
                        </td>
                        {trash && (
                          <td>
                            <button title="Obnoviť" onClick={() => void remove(i, true)}>
                              <RotateCcw size={15} />
                            </button>
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : (
                <>
                  {visible.map((i) => (
                    <div
                      key={i.id}
                      className={'native-invoice-row' + (editor?.id === i.id ? ' selected' : '')}
                    >
                      <button onClick={() => !trash && void open(i.id)}>
                        <div>
                          <b className="numeric">{i.number}</b>
                          <span
                            className={
                              'native-status ' +
                              (status(i) === 'Uhradené'
                                ? 'paid'
                                : status(i) === 'Po splatnosti'
                                  ? 'overdue'
                                  : 'unpaid')
                            }
                          >
                            {status(i) === 'Uhradené'
                              ? 'Uhradená'
                              : status(i) === 'Neuhradené'
                                ? 'Na úhradu'
                                : 'Po splatnosti'}
                          </span>
                          <small className="numeric">{displayDate(i.issueDate ?? i.dueDate)}</small>
                        </div>
                        <div>
                          <span className="row-customer">{i.customer}</span>
                          <b className="numeric">{money(i.total, i.currency)}</b>
                        </div>
                      </button>
                      {trash && (
                        <button
                          className="restore-button"
                          title="Obnoviť"
                          onClick={() => void remove(i, true)}
                        >
                          <RotateCcw size={15} />
                        </button>
                      )}
                    </div>
                  ))}
                </>
              )}
              {!visible.length && (
                <div className="native-empty">
                  {loading ? 'Načítavam faktúry…' : trash ? 'Kôš je prázdny' : 'Žiadne faktúry'}
                </div>
              )}
            </div>
          </aside>
          {!table && !trash && (
            <div className="native-detail">
              <button className="compact-list-back" onClick={() => setCompactDetail(false)}>
                <ArrowLeft size={16} /> Späť na zoznam
              </button>
              {editor ? (
                <InvoiceEditor
                  key={editor.id}
                  initial={editor}
                  accountID={me.user.id}
                  profile={me.profile}
                  templates={templates}
                  registerFlush={(f) => {
                    invoiceFlush.current = f;
                  }}
                  onSaved={saved}
                  onDuplicate={(source) => void newInvoice(source)}
                  onDelete={() => void remove(editor)}
                />
              ) : (
                <div className="native-empty">
                  <FileText size={40} />
                  <h2>Vyberte faktúru</h2>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
      {page === 'settings' && (
        <Settings
          key={me.user.id}
          initial={me.profile}
          version={me.profileVersion}
          templates={templates}
          onSaved={onProfile}
          accountID={me.user.id}
          registerFlush={(f) => {
            settingsFlush.current = f;
          }}
        />
      )}
      {page === 'customers' && (
        <Customers profile={me.profile} version={me.profileVersion} onSaved={onProfile} />
      )}
      {page === 'admin' && me.user.role === 'admin' && <Admin />}
      {exporting && <InvoiceExportDialog initialYear={year} onClose={() => setExporting(false)} />}
      <AppUpdateNotice
        beforeReload={async () => {
          if (invoiceFlush.current && !(await invoiceFlush.current())) {
            setPage('invoices');
            return false;
          }
          return !settingsFlush.current || (await settingsFlush.current());
        }}
      />
    </div>
  );
}
function Customers({
  profile,
  version,
  onSaved,
}: {
  profile: Profile;
  version: number;
  onSaved: (p: Profile, v: number) => void;
}) {
  const [editing, setEditing] = useState<(Company & { id: string }) | null>(null),
    [error, setError] = useState('');
  const [search, setSearch] = useState('');
  const searchable = (value: string) =>
    value.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase('sk');
  const customers = (profile.customers ?? [])
    .filter((c) => searchable(`${c.name} ${c.companyID} ${c.city}`).includes(searchable(search)))
    .sort((a, b) => a.name.localeCompare(b.name, 'sk', { numeric: true, sensitivity: 'base' }));
  async function save(customers: NonNullable<Profile['customers']>) {
    try {
      const next = { ...profile, customers };
      const result = await api<{ version: number }>('/profile', {
        method: 'PUT',
        body: JSON.stringify({ profile: next, version }),
      });
      onSaved(next, result.version);
      setEditing(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }
  return (
    <div className="page native-customers">
      <div className="page-heading">
        <div>
          <h1>Odberatelia</h1>
          <p>{profile.customers?.length ?? 0} kontaktov</p>
        </div>
        <label className="native-search customer-search">
          <Search size={15} aria-hidden="true" />
          <input
            aria-label="Hľadať firmu, IČO, mesto"
            placeholder="Hľadať firmu, IČO, mesto"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </label>
        <button
          className="button"
          onClick={() => setEditing({ ...emptyCompany(), id: crypto.randomUUID() })}
        >
          <Plus size={16} /> Nový odberateľ
        </button>
      </div>
      <ErrorBox error={error} />
      {customers.length === 0 && <div className="native-empty">Žiadni odberatelia</div>}
      {customers.map((c) => (
        <div className="customer-row" key={c.id}>
          <button
            className="customer-open"
            aria-label={`Upraviť odberateľa ${c.name}`}
            onClick={() => setEditing(c)}
          >
            <Building2 size={22} />
            <span>
              <strong>{c.name}</strong>
              <small>
                {c.street}, {c.city} · {c.companyID}
              </small>
            </span>
          </button>
          <button title="Upraviť odberateľa" onClick={() => setEditing(c)}>
            <MoreHorizontal size={18} />
          </button>
          <button
            title="Odstrániť odberateľa"
            onClick={() => {
              if (confirm('Odstrániť odberateľa? Existujúce faktúry sa nezmenia.'))
                void save(profile.customers!.filter((x) => x.id !== c.id));
            }}
          >
            <Trash2 size={16} />
          </button>
        </div>
      ))}
      {editing && (
        <Modal title="Odberateľ" onClose={() => setEditing(null)}>
          <CompanyFields value={editing} onChange={(c) => setEditing({ ...c, id: editing.id })} />
          <button
            className="button"
            onClick={() =>
              void save([...(profile.customers ?? []).filter((c) => c.id !== editing.id), editing])
            }
          >
            Uložiť odberateľa
          </button>
        </Modal>
      )}
    </div>
  );
}
