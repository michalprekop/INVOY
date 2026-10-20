import { z } from 'zod';
import Decimal from 'decimal.js';
import {
  MAX_PROFILE_IMAGE_BYTES,
  MAX_PROFILE_IMAGE_BASE64,
  base64ByteLength,
} from './image-limits';

const text = (max = 250) => z.string().trim().max(max);
const decimal = (max: number, min = 0) =>
  z
    .string()
    .regex(/^\d{1,12}(\.\d{1,4})?$/, 'Použite kladné číslo, najviac 4 desatinné miesta.')
    .refine((v) => new Decimal(v).gte(min) && new Decimal(v).lte(max), 'Číslo je mimo rozsahu.');
const date = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine(
    (v) => !isNaN(Date.parse(v)) && new Date(v).toISOString().slice(0, 10) === v,
    'Neplatný dátum.',
  );
const templateImageSchema = z
  .string()
  .max(180_000)
  .regex(/^data:image\/(png|jpeg);base64,[A-Za-z0-9+/=]+$/)
  .or(z.literal(''));
export const imageSchema = z
  .string()
  .max(MAX_PROFILE_IMAGE_BASE64 + 'data:image/jpeg;base64,'.length)
  .regex(/^data:image\/(png|jpeg);base64,[A-Za-z0-9+/=]+$/)
  .refine(
    (value) => base64ByteLength(value.slice(value.indexOf(',') + 1)) <= MAX_PROFILE_IMAGE_BYTES,
    'Obrázok môže mať najviac 0,5 MB.',
  )
  .or(z.literal(''));
export const companySchema = z
  .object({
    id: z.string().uuid().optional(),
    name: text(),
    street: text(),
    postalCode: text(20),
    city: text(100),
    country: text(100),
    companyID: text(30),
    taxID: text(30),
    vatID: text(30),
    email: text(),
    phone: text(50),
    website: text(),
    registration: text(500),
    vatPayer: z.boolean(),
  })
  .strict();
export function validIBAN(value: string) {
  const iban = value.replace(/\s/g, '').toUpperCase();
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(iban)) return false;
  let n = 0;
  for (const c of iban.slice(4) + iban.slice(0, 4)) {
    const x = /[A-Z]/.test(c) ? c.charCodeAt(0) - 55 : Number(c);
    n = (n * (x >= 10 ? 100 : 10) + x) % 97;
  }
  return n === 1;
}
export const accountSchema = z
  .object({
    id: z.string().uuid(),
    name: text(100).min(1),
    iban: text(50).refine(validIBAN, 'Skontrolujte IBAN.'),
    swift: text(20),
    holderName: text(),
  })
  .strict();
export const templateConfigSchema = z
  .object({
    layout: z.enum(['classic', 'mono', 'manoloBay']),
    accent: z.string().regex(/^#[0-9a-fA-F]{6}$/),
    wordmark: text(80),
    logo: templateImageSchema,
    footer: text(500),
  })
  .strict();
export const nativeTemplateLayout = (layout: TemplateConfig['layout']) =>
  layout === 'manoloBay' ? 'manoloBay' : layout === 'mono' ? 'mono01' : 'boringDefault01';

export const templateSchema = z
  .object({
    name: text(80).min(1),
    description: text(300),
    config: templateConfigSchema,
    archived: z.boolean(),
    version: z.number().int().nonnegative(),
  })
  .strict();
export const profileSchema = z
  .object({
    supplier: companySchema,
    customers: z
      .array(companySchema.extend({ id: z.string().uuid() }))
      .max(5000)
      .optional(),
    appearance: z
      .object({
        accent: z.string().regex(/^#[0-9a-fA-F]{6}$/),
        template: z.enum(['boringDefault01', 'mono01', 'manoloBay']),
      })
      .strict()
      .optional(),
    accounts: z.array(accountSchema).max(10),
    defaultAccountID: z.string().uuid().nullable(),
    dueDays: z.number().int().min(0).max(365),
    currency: z.enum(['EUR', 'CZK', 'USD', 'GBP']),
    numberPrefix: text(20),
    numberDigits: z.number().int().min(1).max(8),
    defaultNote: text(2000),
    issuedBy: text(),
    defaultVAT: decimal(100),
    logo: imageSchema,
    signature: imageSchema,
    defaultTemplateID: z.string().max(64).nullable(),
  })
  .strict()
  .refine(
    (p) => !p.defaultAccountID || p.accounts.some((a) => a.id === p.defaultAccountID),
    'Vyberte existujúci účet.',
  )
  .refine(
    (p) => new Set(p.accounts.map((a) => a.id)).size === p.accounts.length,
    'Duplicitný účet.',
  );
export const itemSchema = z
  .object({
    id: z.string().uuid(),
    name: text(500).min(1),
    detail: text(2000),
    quantity: decimal(1e8, 0.0001),
    unit: text(20),
    unitPrice: decimal(1e10),
    discount: decimal(100),
    vatRate: decimal(100),
  })
  .strict();
const invoiceBase = z
  .object({
    id: z
      .string()
      .uuid()
      .transform((v) => v.toLowerCase()),
    version: z.number().int().nonnegative(),
    number: text(40).min(1),
    orderNumber: text(250).optional(),
    nativeDates: z
      .object({
        createdAt: z.number().finite(),
        updatedAt: z.number().finite(),
        issueDate: z.number().finite(),
        dueDate: z.number().finite(),
        deliveryDate: z.number().finite().optional(),
      })
      .strict()
      .optional(),
    nativeTemplateOverride: z
      .enum(['boringDefault01', 'mono01', 'manoloBay'])
      .nullable()
      .optional(),
    issueDate: date,
    dueDate: date,
    deliveryDate: date.nullable(),
    supplier: companySchema.refine((v) => v.name.length > 0, 'Doplňte dodávateľa.'),
    customer: companySchema.refine((v) => v.name.length > 0, 'Doplňte odberateľa.'),
    account: accountSchema.nullable(),
    items: z.array(itemSchema).min(1).max(150),
    currency: z.enum(['EUR', 'CZK', 'USD', 'GBP']),
    paid: decimal(1e12),
    variableSymbol: z.string().regex(/^\d{0,10}$/),
    constantSymbol: z.string().regex(/^\d{0,4}$/),
    specificSymbol: z.string().regex(/^\d{0,10}$/),
    language: z.enum(['sk', 'en']).optional(),
    paymentMethod: z.enum(['', 'Bankový prevod', 'Hotovosť', 'Karta', 'Dobierka']),
    note: text(4000),
    issuedBy: text(),
    logo: imageSchema,
    signature: imageSchema,
    templateID: z.string().min(1).max(64),
    qrFormat: z.enum(['automatic', 'payBySquare', 'qrPlatba', 'disabled']),
  })
  .strict()
  .refine((v) => v.dueDate >= v.issueDate, 'Splatnosť nemôže byť pred vystavením.')
  .refine(
    (v) => v.paymentMethod !== 'Bankový prevod' || v.account !== null,
    'Vyberte bankový účet.',
  );
export const invoiceSchema = invoiceBase.refine(
  (value) => new Decimal(totals(value).total).lte(1e12),
  'Celková suma faktúry je mimo podporovaného rozsahu.',
);
export type Company = z.infer<typeof companySchema>;
export type Account = z.infer<typeof accountSchema>;
export type Profile = z.infer<typeof profileSchema>;
export type Invoice = z.infer<typeof invoiceSchema>;
export type TemplateConfig = z.infer<typeof templateConfigSchema>;
export type Template = z.infer<typeof templateSchema> & { id: string };
export type SavedInvoice = Invoice & {
  templateSnapshot: TemplateConfig;
  templateName: string;
  updatedAt: string;
  deletedAt?: string | null;
};
export type User = {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'user';
  status: 'pending' | 'active' | 'suspended';
  created_at: string;
};
export type AdminUser = User & {
  invoice_count: number;
  customer_count: number;
  last_seen_at: string | null;
};
export type InvoiceSummary = {
  id: string;
  number: string;
  updated_at: string;
  version: number;
  customer: string;
  total: string;
  currency: string;
  paid: string;
  dueDate: string;
  issueDate?: string;
  searchText?: string;
  deleted_at: string | null;
};
export const emptyCompany = (): Company => ({
  name: '',
  street: '',
  postalCode: '',
  city: '',
  country: 'Slovensko',
  companyID: '',
  taxID: '',
  vatID: '',
  email: '',
  phone: '',
  website: '',
  registration: '',
  vatPayer: false,
});
export const emptyProfile = (): Profile => ({
  supplier: emptyCompany(),
  accounts: [],
  defaultAccountID: null,
  dueDays: 14,
  currency: 'EUR',
  numberPrefix: '',
  numberDigits: 3,
  defaultNote: '',
  issuedBy: '',
  defaultVAT: '0',
  logo: '',
  signature: '',
  defaultTemplateID: null,
});
export const baseConfig: TemplateConfig = {
  layout: 'classic',
  accent: '#1b4338',
  wordmark: '',
  logo: '',
  footer: '',
};
export const defaultTemplate: Template = {
  id: 'classic',
  name: 'Boring default 01',
  description: 'Čistá faktúra s vaším logom a farbou.',
  config: baseConfig,
  archived: false,
  version: 1,
};
export function totals(invoice: Pick<z.infer<typeof invoiceBase>, 'items' | 'supplier' | 'paid'>) {
  const d = (v: string) => new Decimal(/^\d+(\.\d*)?$/.test(v) ? v : '0');
  let net = new Decimal(0),
    vat = new Decimal(0);
  const rates = new Map<string, { net: Decimal; vat: Decimal }>();
  const rows = invoice.items.map((item) => {
    const base = d(item.quantity)
      .mul(d(item.unitPrice))
      .mul(new Decimal(1).minus(d(item.discount).div(100)))
      .toDecimalPlaces(2, Decimal.ROUND_HALF_UP);
    const tax = invoice.supplier.vatPayer
      ? base.mul(d(item.vatRate)).div(100).toDecimalPlaces(2, Decimal.ROUND_HALF_UP)
      : new Decimal(0);
    net = net.plus(base);
    vat = vat.plus(tax);
    if (invoice.supplier.vatPayer) {
      const rate = d(item.vatRate).toString(),
        group = rates.get(rate) ?? { net: new Decimal(0), vat: new Decimal(0) };
      rates.set(rate, { net: group.net.plus(base), vat: group.vat.plus(tax) });
    }
    return { net: base.toFixed(2), vat: tax.toFixed(2), total: base.plus(tax).toFixed(2) };
  });
  const total = net.plus(vat),
    remaining = Decimal.max(0, total.minus(d(invoice.paid)));
  return {
    net: net.toFixed(2),
    vat: vat.toFixed(2),
    total: total.toFixed(2),
    remaining: remaining.toFixed(2),
    overpaid: Decimal.max(0, d(invoice.paid).minus(total)).toFixed(2),
    rows,
    taxRates: [...rates]
      .sort(([a], [b]) => Number(a) - Number(b))
      .map(([rate, x]) => ({ rate, net: x.net.toFixed(2), vat: x.vat.toFixed(2) })),
  };
}
export const money = (v: string, currency = 'EUR') =>
  new Intl.NumberFormat('sk-SK', { style: 'currency', currency }).format(
    Number.isFinite(Number(v)) ? Number(v) : 0,
  );
export const displayDate = (v: string) => (v ? v.split('-').reverse().join('.') : '');
export function freshInvoice(profile: Profile, number: string, templateID: string): Invoice {
  const today = new Date(),
    due = new Date();
  due.setDate(due.getDate() + profile.dueDays);
  const localDate = (d: Date) =>
    new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 10);
  return {
    id: crypto.randomUUID(),
    version: 0,
    number,
    issueDate: localDate(today),
    dueDate: localDate(due),
    deliveryDate: null,
    supplier: structuredClone(profile.supplier),
    customer: emptyCompany(),
    account: structuredClone(
      profile.accounts.find((a) => a.id === profile.defaultAccountID) ??
        profile.accounts[0] ??
        null,
    ),
    items: [
      {
        id: crypto.randomUUID(),
        name: '',
        detail: '',
        quantity: '1',
        unit: 'ks',
        unitPrice: '0',
        discount: '0',
        vatRate: profile.defaultVAT,
      },
    ],
    currency: profile.currency,
    paid: '0',
    variableSymbol: number.replace(/\D/g, '').slice(-10),
    constantSymbol: '',
    specificSymbol: '',
    paymentMethod: 'Bankový prevod',
    note: profile.defaultNote,
    issuedBy: profile.issuedBy,
    logo: profile.logo,
    signature: profile.signature,
    templateID,
    qrFormat: 'automatic',
  };
}
export function invoiceInput(saved: SavedInvoice): Invoice {
  const { templateSnapshot, templateName, updatedAt, deletedAt, ...input } = saved;
  return input;
}
