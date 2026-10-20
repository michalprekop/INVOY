import { z } from 'zod';
import { createHash } from 'node:crypto';
import {
  MAX_PROFILE_IMAGE_BYTES,
  MAX_PROFILE_IMAGE_BASE64,
  base64ByteLength,
} from './image-limits';
import {
  companySchema,
  accountSchema,
  invoiceSchema,
  profileSchema,
  type Profile,
  type Invoice,
  type SavedInvoice,
  type Template,
  templateConfigSchema,
  nativeTemplateLayout,
} from './model';

const number = z.number().finite();
const nativeCompany = companySchema.extend({ id: z.string().uuid() });
const nativeAccount = accountSchema.extend({ holderName: z.string().optional() });
const data = z
  .string()
  .max(MAX_PROFILE_IMAGE_BASE64)
  .regex(/^[A-Za-z0-9+/=]*$/)
  .refine(
    (value) => base64ByteLength(value) <= MAX_PROFILE_IMAGE_BYTES,
    'Obrázok môže mať najviac 0,5 MB.',
  )
  .optional();
const layout = z.enum(['boringDefault01', 'mono01', 'manoloBay']);
const cloudStyle = z
  .object({ id: z.string().max(64), name: z.string().max(80), config: templateConfigSchema })
  .strict();
export const nativeInvoiceSchema = z
  .object({
    id: z.string().uuid(),
    number: z.string(),
    variableSymbol: z.string(),
    constantSymbol: z.string(),
    specificSymbol: z.string(),
    orderNumber: z.string(),
    issueDate: number,
    dueDate: number,
    deliveryDate: number.optional(),
    createdAt: number,
    updatedAt: number,
    supplier: nativeCompany,
    customer: nativeCompany,
    account: nativeAccount.optional(),
    items: z
      .array(
        z
          .object({
            id: z.string().uuid(),
            name: z.string(),
            detail: z.string(),
            quantity: number,
            unit: z.string(),
            unitPrice: number,
            discount: number,
            vatRate: number,
          })
          .strict(),
      )
      .max(150),
    currency: z.enum(['EUR', 'CZK', 'USD', 'GBP']),
    language: z.enum(['sk', 'en']).optional(),
    paymentMethod: z.enum([
      '',
      'Bankový prevod',
      'Hotovosť',
      'Platobná karta',
      'Karta',
      'Dobierka',
    ]),
    paymentQRFormat: z.enum(['automatic', 'payBySquare', 'qrPlatba', 'disabled']).optional(),
    templateOverride: layout.optional(),
    cloudStyle: cloudStyle.optional(),
    note: z.string(),
    issuedBy: z.string(),
    paid: number,
    logo: data,
    signature: data,
  })
  .strict();
export const nativeSettingsSchema = z
  .object({
    supplier: nativeCompany,
    accounts: z.array(nativeAccount).max(10),
    defaultAccountID: z.string().uuid().optional(),
    dueDays: z.number().int(),
    currency: z.enum(['EUR', 'CZK', 'USD', 'GBP']),
    numberPrefix: z.string(),
    numberDigits: z.number().int(),
    cloudTemplateID: z.string().max(64).optional(),
    defaultNote: z.string(),
    issuedBy: z.string(),
    defaultVAT: number,
    invoiceAccentHex: z.string().optional(),
    invoiceTemplate: layout.optional(),
    logo: data,
    signature: data,
  })
  .strict();
export const nativeDatabaseSchema = z
  .object({
    schemaVersion: z.literal(1),
    settings: nativeSettingsSchema,
    customers: z.array(nativeCompany).max(5000),
    invoices: z.array(nativeInvoiceSchema).max(5000),
  })
  .strict();
export type NativeInvoice = z.infer<typeof nativeInvoiceSchema>;
export type NativeSettings = z.infer<typeof nativeSettingsSchema>;
const epoch = 978307200;
const dayFormatter = new Intl.DateTimeFormat('sv-SE', {
  timeZone: 'Europe/Bratislava',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});
export const nativeDay = (n: number) => dayFormatter.format(new Date((n + epoch) * 1000));
const nativeDate = (day: string, prior?: number) =>
  prior !== undefined && nativeDay(prior) === day
    ? prior
    : Date.parse(day + 'T12:00:00Z') / 1000 - epoch;
const image = (s?: string) =>
  !s ? '' : `data:image/${s.startsWith('/9j/') ? 'jpeg' : 'png'};base64,${s}`;
const bytes = (s: string) => (s ? s.split(',')[1] : undefined);
export const templateLayout = (template: Template) => nativeTemplateLayout(template.config.layout);
export function chooseTemplate(
  templates: Template[],
  desired: string | undefined,
  preferred?: string | null,
) {
  return (
    templates.find((t) => t.id === preferred && (!desired || templateLayout(t) === desired)) ??
    templates.find((t) => templateLayout(t) === (desired ?? 'boringDefault01'))
  );
}
export function fromNativeInvoice(n: NativeInvoice, version: number, templateID: string): Invoice {
  const { paymentQRFormat, templateOverride, createdAt, updatedAt, cloudStyle, ...fields } = n;
  return invoiceSchema.parse({
    ...fields,
    version,
    templateID,
    orderNumber: n.orderNumber,
    qrFormat: n.paymentQRFormat ?? 'automatic',
    nativeTemplateOverride: n.templateOverride ?? null,
    nativeDates: {
      createdAt: n.createdAt,
      updatedAt: n.updatedAt,
      issueDate: n.issueDate,
      dueDate: n.dueDate,
      ...(n.deliveryDate === undefined ? {} : { deliveryDate: n.deliveryDate }),
    },
    issueDate: nativeDay(n.issueDate),
    dueDate: nativeDay(n.dueDate),
    deliveryDate: n.deliveryDate === undefined ? null : nativeDay(n.deliveryDate),
    account: n.account ? { ...n.account, holderName: n.account.holderName ?? '' } : null,
    paid: String(n.paid),
    paymentMethod: n.paymentMethod === 'Platobná karta' ? 'Karta' : n.paymentMethod,
    items: n.items.map((i) => ({
      ...i,
      quantity: String(i.quantity),
      unitPrice: String(i.unitPrice),
      discount: String(i.discount),
      vatRate: String(i.vatRate),
    })),
    logo: image(n.logo),
    signature: image(n.signature),
  });
}
export function fromNativeSettings(
  n: NativeSettings,
  customers: z.infer<typeof nativeCompany>[],
  defaultTemplateID: string | null,
): Profile {
  return profileSchema.parse({
    supplier: n.supplier,
    customers,
    accounts: n.accounts.map((a) => ({ ...a, holderName: a.holderName ?? '' })),
    defaultAccountID: n.defaultAccountID ?? null,
    dueDays: n.dueDays,
    currency: n.currency,
    numberPrefix: n.numberPrefix,
    numberDigits: n.numberDigits,
    defaultNote: n.defaultNote,
    issuedBy: n.issuedBy,
    defaultVAT: String(n.defaultVAT),
    logo: image(n.logo),
    signature: image(n.signature),
    defaultTemplateID,
    appearance: {
      accent: n.invoiceAccentHex ?? '#146B59',
      template: n.invoiceTemplate ?? 'boringDefault01',
    },
  });
}
const company = (c: Profile['supplier']) => {
  const h = createHash('sha256').update(JSON.stringify(c)).digest('hex');
  return {
    ...c,
    id:
      c.id ??
      `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`,
  };
};
export function toNativeInvoice(i: SavedInvoice): NativeInvoice {
  return nativeInvoiceSchema.parse({
    id: i.id,
    number: i.number,
    variableSymbol: i.variableSymbol,
    constantSymbol: i.constantSymbol,
    specificSymbol: i.specificSymbol,
    orderNumber: i.orderNumber ?? '',
    issueDate: nativeDate(i.issueDate, i.nativeDates?.issueDate),
    dueDate: nativeDate(i.dueDate, i.nativeDates?.dueDate),
    deliveryDate: i.deliveryDate
      ? nativeDate(i.deliveryDate, i.nativeDates?.deliveryDate)
      : undefined,
    createdAt: i.nativeDates?.createdAt ?? Date.parse(i.updatedAt) / 1000 - epoch,
    updatedAt: Date.parse(i.updatedAt) / 1000 - epoch,
    supplier: company(i.supplier),
    customer: company(i.customer),
    account: i.account ?? undefined,
    items: i.items.map((x) => ({
      ...x,
      quantity: Number(x.quantity),
      unitPrice: Number(x.unitPrice),
      discount: Number(x.discount),
      vatRate: Number(x.vatRate),
    })),
    currency: i.currency,
    paid: Number(i.paid),
    language: i.language,
    paymentMethod: i.paymentMethod === 'Karta' ? 'Platobná karta' : i.paymentMethod,
    paymentQRFormat: i.qrFormat,
    cloudStyle: { id: i.templateID, name: i.templateName, config: i.templateSnapshot },
    templateOverride: nativeTemplateLayout(i.templateSnapshot.layout),
    note: i.note,
    issuedBy: i.issuedBy,
    logo: bytes(i.logo),
    signature: bytes(i.signature),
  });
}
export function toNativeSettings(p: Profile): NativeSettings {
  return {
    cloudTemplateID: p.defaultTemplateID ?? undefined,
    supplier: company(p.supplier),
    accounts: p.accounts,
    defaultAccountID: p.defaultAccountID ?? undefined,
    dueDays: p.dueDays,
    currency: p.currency,
    numberPrefix: p.numberPrefix,
    numberDigits: p.numberDigits,
    defaultNote: p.defaultNote,
    issuedBy: p.issuedBy,
    defaultVAT: Number(p.defaultVAT),
    invoiceAccentHex: p.appearance?.accent,
    invoiceTemplate: p.appearance?.template,
    logo: bytes(p.logo),
    signature: bytes(p.signature),
  };
}
