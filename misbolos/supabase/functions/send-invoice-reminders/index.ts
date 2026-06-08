/// <reference lib="deno.ns" />
// @deno-types="https://esm.sh/@supabase/supabase-js@2?dts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type UserSettings = {
  user_id: string;
  emisor_email?: string | null;
  email_invoice_reminders_enabled?: boolean | null;
  invoice_reminder_frequency?: string | null;
  invoice_last_reminder_sent_at?: string | null;
  last_invoice_reminder_email_sent_at?: string | null;
};

type PendingItem = {
  id: string;
  invoiceId?: string;
  invoiceNumber: string;
  clientName: string;
  date: string;
  amount: number;
  status: string;
};

type InvoiceDiagnostic = {
  invoiceId: string;
  numero: string;
  status: string;
  amount: number;
  dueDate: string;
  clientEmail: string;
  ageDays: number;
  eligible: boolean;
  reason?: string;
};

type GigDiagnostic = {
  gigId: string;
  status: string;
  amount: number;
  eligible: boolean;
  reason?: string;
};

type UserDiagnostic = {
  userId: string;
  emailEnabled: boolean;
  recipientEmail: string;
  totalInvoices: number;
  byStatus: Record<string, number>;
  withClientEmail: number;
  pendingInvoices: number;
  overdueInvoices: number;
  eligibleInvoices: number;
  eligibleGigCandidates: number;
  discarded: Array<{
    kind: "invoice" | "gig" | "user";
    id?: string;
    reason: string;
    status?: string;
    dueDate?: string;
    clientEmail?: string;
  }>;
  invoices: InvoiceDiagnostic[];
  gigs: GigDiagnostic[];
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const brevoApiKey = Deno.env.get("BREVO_API_KEY");
    const fromEmail = Deno.env.get("INVOICE_FROM_EMAIL") ?? Deno.env.get("EMAIL_FROM");
    const cronSecret = Deno.env.get("INVOICE_REMINDER_CRON_SECRET");

    if (!supabaseUrl || !serviceRoleKey) {
      return json({ ok: false, error: "Supabase service config missing." }, 500);
    }
    if (!brevoApiKey || !fromEmail) {
      return json({ ok: false, error: "Email provider is not configured." }, 500);
    }
    if (!cronSecret) {
      return json({ ok: false, error: "Cron secret is not configured." }, 500);
    }
    if (!isAuthorizedCronRequest(req, cronSecret)) {
      return json({ ok: false, error: "Unauthorized." }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const onlyUserId = typeof body?.user_id === "string" ? body.user_id.trim() : "";
    const force = body?.force === true;
    const debug = body?.debug === true || force === true || body?.diagnostic === true;

    const client = createClient(supabaseUrl, serviceRoleKey);
    const settingsSelect =
      "user_id, emisor_email, email_invoice_reminders_enabled, invoice_reminder_frequency, invoice_last_reminder_sent_at, last_invoice_reminder_email_sent_at";
    let query = client.from("user_settings").select(settingsSelect);
    if (!debug) {
      query = query.eq("email_invoice_reminders_enabled", true);
    }
    if (onlyUserId) query = query.eq("user_id", onlyUserId);

    const { data: settingsRows, error: settingsError } = await query;
    if (settingsError) throw settingsError;

    const results = [];
    const diagnostics: UserDiagnostic[] = [];
    for (const settings of (settingsRows ?? []) as UserSettings[]) {
      const userDiagnostic = debug
        ? await diagnoseUser(client, settings, force)
        : null;
      if (userDiagnostic) {
        diagnostics.push(userDiagnostic);
        console.log(
          "[invoice-reminders-debug]",
          JSON.stringify({
            userId: userDiagnostic.userId,
            emailEnabled: userDiagnostic.emailEnabled,
            recipientEmail: userDiagnostic.recipientEmail,
            totalInvoices: userDiagnostic.totalInvoices,
            byStatus: userDiagnostic.byStatus,
            withClientEmail: userDiagnostic.withClientEmail,
            pendingInvoices: userDiagnostic.pendingInvoices,
            overdueInvoices: userDiagnostic.overdueInvoices,
            eligibleInvoices: userDiagnostic.eligibleInvoices,
            eligibleGigCandidates: userDiagnostic.eligibleGigCandidates,
            discardedCount: userDiagnostic.discarded.length,
            discardedReasons: userDiagnostic.discarded.map((entry) => entry.reason).slice(0, 20),
          }),
        );
      }

      if (settings.email_invoice_reminders_enabled !== true) {
        results.push({ user_id: settings.user_id, skipped: "email_reminders_disabled" });
        continue;
      }

      const recipient = await recipientEmailForUser(client, settings);
      if (!recipient) {
        results.push({ user_id: settings.user_id, skipped: "missing_email" });
        continue;
      }
      if (!isDue(settings)) {
        results.push({ user_id: settings.user_id, skipped: "frequency_not_due" });
        continue;
      }

      const pending = await pendingItemsForUser(client, settings.user_id);
      if (pending.length === 0) {
        results.push({ user_id: settings.user_id, skipped: "no_pending_invoices" });
        continue;
      }

      const subject = "Facturas pendientes en MisBolos";
      const total = pending.reduce((sum, item) => sum + item.amount, 0);
      const { htmlContent, textContent } = buildEmailMessage(pending, total);

      const response = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
          "api-key": brevoApiKey,
          accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          sender: parseSender(fromEmail),
          to: [{ email: recipient }],
          subject,
          htmlContent,
          textContent,
        }),
      });

      const providerData = await response.json().catch(() => ({}));
      if (!response.ok) {
        await logReminder(client, settings, recipient, subject, pending, total, "failed", providerData?.message ?? providerData?.code ?? "Email provider failed");
        results.push({ user_id: settings.user_id, sent: false, error: providerData?.message ?? providerData?.code ?? "Email provider failed" });
        continue;
      }

      const now = new Date().toISOString();
      await logReminder(client, settings, recipient, subject, pending, total, "sent", null, now);
      await client
        .from("user_settings")
        .update({
          invoice_last_reminder_sent_at: now,
          last_invoice_reminder_email_sent_at: now,
        })
        .eq("user_id", settings.user_id);
      results.push({ user_id: settings.user_id, sent: true, count: pending.length, total });
    }

    const response: Record<string, unknown> = {
      ok: true,
      processed: results.length,
      results,
    };
    if (debug) {
      const allInvoices = diagnostics.reduce((sum, item) => sum + item.totalInvoices, 0);
      const byStatus = diagnostics.reduce((acc, item) => {
        for (const [status, count] of Object.entries(item.byStatus)) {
          acc[status] = (acc[status] ?? 0) + count;
        }
        return acc;
      }, {} as Record<string, number>);
      const withClientEmail = diagnostics.reduce((sum, item) => sum + item.withClientEmail, 0);
      const pendingInvoices = diagnostics.reduce((sum, item) => sum + item.pendingInvoices, 0);
      const overdueInvoices = diagnostics.reduce((sum, item) => sum + item.overdueInvoices, 0);
      const eligibleInvoices = diagnostics.reduce((sum, item) => sum + item.eligibleInvoices, 0);
      const eligibleGigCandidates = diagnostics.reduce((sum, item) => sum + item.eligibleGigCandidates, 0);
      const discarded = diagnostics.flatMap((item) => item.discarded.map((entry) => ({
        userId: item.userId,
        ...entry,
      })));
      response.debug = true;
      response.totalUsersFound = settingsRows?.length ?? 0;
      response.usersWithEmailEnabled = (settingsRows ?? []).filter((row: UserSettings) =>
        row.email_invoice_reminders_enabled === true
      ).length;
      response.totalInvoices = allInvoices;
      response.byStatus = byStatus;
      response.withClientEmail = withClientEmail;
      response.pendingCandidates = pendingInvoices;
      response.overdueCandidates = overdueInvoices;
      response.eligibleInvoices = eligibleInvoices;
      response.eligibleGigCandidates = eligibleGigCandidates;
      response.discarded = discarded;
      response.diagnostics = {
        users: diagnostics,
      };
    }

    return json(response);
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ ok: false, error: message }, 400);
  }
});

function isAuthorizedCronRequest(req: Request, cronSecret: string) {
  const provided = req.headers.get("x-cron-secret")?.trim() ??
    req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim() ??
    "";
  return provided.length > 0 && timingSafeEqual(provided, cronSecret.trim());
}

function timingSafeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function diagnoseUser(
  client: ReturnType<typeof createClient>,
  settings: UserSettings,
  force: boolean,
): Promise<UserDiagnostic> {
  const recipient = await recipientEmailForUser(client, settings);
  const emailEnabled = settings.email_invoice_reminders_enabled === true;
  const discarded: UserDiagnostic["discarded"] = [];
  const invoices: InvoiceDiagnostic[] = [];
  const gigs: GigDiagnostic[] = [];

  if (!emailEnabled) {
    discarded.push({ kind: "user", reason: "email_reminders_disabled" });
  }
  if (!recipient) {
    discarded.push({ kind: "user", reason: "missing_recipient_email" });
  }
  if (!isDue(settings)) {
    discarded.push({ kind: "user", reason: "frequency_not_due" });
  }

  const [
    { data: invoiceRows, error: invoiceError },
    { data: gigRows, error: gigError },
  ] = await Promise.all([
    client
      .from("invoices")
      .select("id, numero, client_id, fecha_emision, total, status, deleted_at")
      .eq("user_id", settings.user_id),
    client
      .from("gigs")
      .select("id, client_id, fecha, cachet, status, invoice_id, facturable, deleted_at")
      .eq("user_id", settings.user_id),
  ]);
  if (invoiceError) throw invoiceError;
  if (gigError) throw gigError;

  const allInvoiceRows = (invoiceRows ?? []) as Record<string, unknown>[];
  const allGigRows = (gigRows ?? []) as Record<string, unknown>[];

  const clientRows = await client
    .from("clients")
    .select("id, nombre, alias, email")
    .eq("user_id", settings.user_id);
  const clientById = new Map((clientRows.data ?? []).map((c: Record<string, unknown>) => [String(c.id), c]));
  const nameFor = (clientId: string) => {
    const c = clientById.get(clientId) as Record<string, unknown> | undefined;
    const alias = String(c?.alias ?? "").trim();
    if (alias) return alias;
    return String(c?.nombre ?? "Cliente").trim() || "Cliente";
  };
  const emailFor = (clientId: string) => {
    const c = clientById.get(clientId) as Record<string, unknown> | undefined;
    return String(c?.email ?? "").trim();
  };

  const now = new Date();
  const byStatus: Record<string, number> = {};
  let withClientEmail = 0;
  for (const invoice of allInvoiceRows) {
    const deletedAt = invoice.deleted_at != null ? String(invoice.deleted_at) : "";
    const status = String(invoice.status ?? "");
    const amount = Number(invoice.total ?? 0);
    const fechaEmision = String(invoice.fecha_emision ?? "");
    const clientId = String(invoice.client_id ?? "");
    const clientEmail = emailFor(clientId);
    const ageDays = fechaEmision ? Math.max(0, Math.floor((now.getTime() - new Date(fechaEmision).getTime()) / (24 * 60 * 60 * 1000))) : 0;
    const diagnostic: InvoiceDiagnostic = {
      invoiceId: String(invoice.id ?? ""),
      numero: String(invoice.numero ?? ""),
      status,
      amount,
      dueDate: fechaEmision,
      clientEmail,
      ageDays,
      eligible: false,
    };
    if (clientEmail) withClientEmail += 1;
    byStatus[status || "unknown"] = (byStatus[status || "unknown"] ?? 0) + 1;

    if (deletedAt) {
      diagnostic.reason = "invoice_deleted";
    } else if (amount <= 0) {
      diagnostic.reason = "invoice_amount_zero";
    } else if (status !== "enviada") {
      diagnostic.reason = `invoice_status_${status || "unknown"}`;
    } else {
      diagnostic.eligible = true;
    }
    invoices.push(diagnostic);
  }

  for (const gig of allGigRows) {
    const deletedAt = gig.deleted_at != null ? String(gig.deleted_at) : "";
    const status = String(gig.status ?? "");
    const amount = Number(gig.cachet ?? 0);
    const facturable = gig.facturable === true;
    const invoiceId = gig.invoice_id != null ? String(gig.invoice_id) : "";
    const diagnostic: GigDiagnostic = {
      gigId: String(gig.id ?? ""),
      status,
      amount,
      eligible: false,
    };

    if (deletedAt) {
      diagnostic.reason = "gig_deleted";
    } else if (!facturable) {
      diagnostic.reason = "gig_not_facturable";
    } else if (invoiceId) {
      diagnostic.reason = "gig_invoice_already_created";
    } else if (amount <= 0) {
      diagnostic.reason = "gig_amount_zero";
    } else if (!["confirmado", "facturado"].includes(status)) {
      diagnostic.reason = `gig_status_${status || "unknown"}`;
    } else {
      diagnostic.eligible = true;
    }
    gigs.push(diagnostic);
  }

  const pendingInvoices = invoices.filter((item) => item.eligible);
  const overdueInvoices = pendingInvoices.filter((item) => item.ageDays > 7);
  const eligibleInvoices = pendingInvoices.length + gigs.filter((item) => item.eligible).length;
  const eligibleGigCandidates = gigs.filter((item) => item.eligible).length;

  for (const invoice of invoices) {
    if (invoice.eligible) continue;
    discarded.push({
      kind: "invoice",
      id: invoice.invoiceId,
      reason: invoice.reason ?? "invoice_not_eligible",
      status: invoice.status,
      dueDate: invoice.dueDate,
      clientEmail: invoice.clientEmail,
    });
  }
  for (const gig of gigs) {
    if (gig.eligible) continue;
    discarded.push({
      kind: "gig",
      id: gig.gigId,
      reason: gig.reason ?? "gig_not_eligible",
      status: gig.status,
    });
  }

  return {
    userId: settings.user_id,
    emailEnabled,
    recipientEmail: recipient,
    totalInvoices: invoices.length,
    byStatus,
    withClientEmail,
    pendingInvoices: pendingInvoices.length,
    overdueInvoices: overdueInvoices.length,
    eligibleInvoices,
    eligibleGigCandidates,
    discarded,
    invoices,
    gigs,
  };
}

async function recipientEmailForUser(
  client: ReturnType<typeof createClient>,
  settings: UserSettings,
) {
  const billingEmail = (settings.emisor_email ?? "").trim();
  if (billingEmail) return billingEmail;

  const { data, error } = await client.auth.admin.getUserById(settings.user_id);
  if (error) return "";
  return (data.user?.email ?? "").trim();
}

function isDue(settings: UserSettings) {
  const frequency = normalizeFrequency(settings.invoice_reminder_frequency);
  const last =
    settings.invoice_last_reminder_sent_at ??
    settings.last_invoice_reminder_email_sent_at;
  if (!last) return true;
  const lastDate = new Date(last);
  if (Number.isNaN(lastDate.getTime())) return true;
  const days = frequency === "biweekly" ? 15 : frequency === "monthly" ? 30 : 7;
  return Date.now() - lastDate.getTime() >= days * 24 * 60 * 60 * 1000;
}

function normalizeFrequency(value?: string | null) {
  const frequency = (value ?? "weekly").trim().toLowerCase();
  if (frequency === "biweekly" || frequency === "monthly") return frequency;
  return "weekly";
}

async function pendingItemsForUser(client: ReturnType<typeof createClient>, userId: string) {
  const [{ data: invoices, error: invoiceError }, { data: gigs, error: gigError }, { data: clients, error: clientError }] = await Promise.all([
    client.from("invoices").select("id, numero, client_id, fecha_emision, total, status").eq("user_id", userId).eq("status", "enviada").is("deleted_at", null),
    client.from("gigs").select("id, client_id, fecha, cachet, status, invoice_id, facturable").eq("user_id", userId).eq("facturable", true).in("status", ["confirmado", "facturado"]).is("invoice_id", null).is("deleted_at", null),
    client.from("clients").select("id, nombre, alias").eq("user_id", userId),
  ]);
  if (invoiceError) throw invoiceError;
  if (gigError) throw gigError;
  if (clientError) throw clientError;

  const clientById = new Map((clients ?? []).map((c: Record<string, unknown>) => [String(c.id), c]));
  const nameFor = (clientId: string) => {
    const c = clientById.get(clientId) as Record<string, unknown> | undefined;
    const alias = String(c?.alias ?? "").trim();
    if (alias) return alias;
    return String(c?.nombre ?? "Cliente").trim() || "Cliente";
  };

  const pendingInvoices: PendingItem[] = (invoices ?? []).map((invoice: Record<string, unknown>) => ({
    id: String(invoice.id),
    invoiceId: String(invoice.id),
    invoiceNumber: String(invoice.numero ?? ""),
    clientName: nameFor(String(invoice.client_id ?? "")),
    date: String(invoice.fecha_emision ?? ""),
    amount: Number(invoice.total ?? 0),
    status: "Pendiente de cobro",
  }));

  const pendingDrafts: PendingItem[] = (gigs ?? []).map((gig: Record<string, unknown>) => ({
    id: String(gig.id),
    invoiceNumber: "Sin factura",
    clientName: nameFor(String(gig.client_id ?? "")),
    date: String(gig.fecha ?? ""),
    amount: Number(gig.cachet ?? 0),
    status: "Factura pendiente de generar",
  }));

  return [...pendingInvoices, ...pendingDrafts].filter((item) => item.amount > 0);
}

function buildEmailMessage(items: PendingItem[], total: number) {
  const rowsHtml = items.map((item) => {
    const date = formatDate(item.date);
    return `
      <tr>
        <td style="padding:14px 16px;border-bottom:1px solid #E5E7EB;color:#0F172A;font-size:14px;line-height:20px;">${escapeHtml(item.clientName)}</td>
        <td style="padding:14px 16px;border-bottom:1px solid #E5E7EB;color:#475569;font-size:14px;line-height:20px;">${escapeHtml(item.invoiceNumber)}</td>
        <td style="padding:14px 16px;border-bottom:1px solid #E5E7EB;color:#475569;font-size:14px;line-height:20px;white-space:nowrap;">${escapeHtml(date)}</td>
        <td style="padding:14px 16px;border-bottom:1px solid #E5E7EB;color:#0F172A;font-size:14px;line-height:20px;text-align:right;white-space:nowrap;font-weight:700;">${formatCurrency(item.amount)}</td>
        <td style="padding:14px 16px;border-bottom:1px solid #E5E7EB;text-align:right;white-space:nowrap;">
          <span style="display:inline-block;padding:6px 10px;border-radius:999px;background:#FEF3C7;color:#92400E;font-size:12px;font-weight:700;line-height:16px;">${escapeHtml(item.status)}</span>
        </td>
      </tr>
    `;
  }).join("");

  const summary = `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 24px 0;">
      <tr>
        <td style="padding:0 8px 0 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F8FAFC;border:1px solid #E5E7EB;border-radius:14px;">
            <tr>
              <td style="padding:18px 20px;">
                <div style="font-size:12px;line-height:16px;color:#64748B;text-transform:uppercase;letter-spacing:.06em;font-weight:700;margin-bottom:8px;">Nº de facturas pendientes</div>
                <div style="font-size:28px;line-height:34px;color:#0F172A;font-weight:800;">${items.length}</div>
              </td>
            </tr>
          </table>
        </td>
        <td style="padding:0 0 0 8px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F8FAFC;border:1px solid #E5E7EB;border-radius:14px;">
            <tr>
              <td style="padding:18px 20px;text-align:right;">
                <div style="font-size:12px;line-height:16px;color:#64748B;text-transform:uppercase;letter-spacing:.06em;font-weight:700;margin-bottom:8px;">Total pendiente</div>
                <div style="font-size:28px;line-height:34px;color:#0F172A;font-weight:800;white-space:nowrap;">${formatCurrency(total)}</div>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  `;

  const htmlContent = `
    <div style="margin:0;padding:0;background:#F3F6FA;width:100%!important;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F3F6FA;width:100%;margin:0;padding:24px 12px;">
        <tr>
          <td align="center" style="padding:0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:680px;width:100%;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #E5E7EB;">
              <tr>
                <td style="padding:28px 28px 8px 28px;">
                  <div style="font-size:28px;line-height:34px;font-weight:800;color:#0F172A;letter-spacing:-0.02em;">MisBolos</div>
                  <div style="font-size:15px;line-height:22px;color:#64748B;margin-top:6px;">Resumen semanal de facturas pendientes</div>
                </td>
              </tr>
              <tr>
                <td style="padding:20px 28px 0 28px;">
                  ${summary}
                </td>
              </tr>
              <tr>
                <td style="padding:0 28px 28px 28px;">
                  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:separate;border-spacing:0;border:1px solid #E5E7EB;border-radius:14px;overflow:hidden;">
                    <thead>
                      <tr>
                        <th align="left" style="padding:14px 16px;background:#0F172A;color:#FFFFFF;font-size:13px;line-height:18px;font-weight:700;">Cliente</th>
                        <th align="left" style="padding:14px 16px;background:#0F172A;color:#FFFFFF;font-size:13px;line-height:18px;font-weight:700;">Factura</th>
                        <th align="left" style="padding:14px 16px;background:#0F172A;color:#FFFFFF;font-size:13px;line-height:18px;font-weight:700;">Fecha</th>
                        <th align="right" style="padding:14px 16px;background:#0F172A;color:#FFFFFF;font-size:13px;line-height:18px;font-weight:700;white-space:nowrap;">Importe</th>
                        <th align="right" style="padding:14px 16px;background:#0F172A;color:#FFFFFF;font-size:13px;line-height:18px;font-weight:700;white-space:nowrap;">Estado</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${rowsHtml}
                    </tbody>
                  </table>
                </td>
              </tr>
              <tr>
                <td style="padding:0 28px 28px 28px;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="width:100%;">
                    <tr>
                      <td style="padding:0 0 20px 0;">
                        <a href="misbolos://" style="display:inline-block;background:#0F172A;color:#FFFFFF;text-decoration:none;font-size:14px;line-height:20px;font-weight:700;padding:12px 18px;border-radius:10px;">Abrir MisBolos</a>
                      </td>
                    </tr>
                    <tr>
                      <td style="font-size:12px;line-height:18px;color:#94A3B8;">
                        Recibes este correo porque tienes activados los recordatorios de facturas en MisBolos.
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </div>
  `;

  const textContent = [
    "MisBolos",
    "Resumen semanal de facturas pendientes",
    "",
    `Nº de facturas pendientes: ${items.length}`,
    `Total pendiente: ${formatCurrency(total)}`,
    "",
    ...items.map((item) =>
      [
        `Cliente: ${item.clientName}`,
        `Factura: ${item.invoiceNumber}`,
        `Fecha: ${formatDate(item.date)}`,
        `Importe: ${formatCurrency(item.amount)}`,
        `Estado: ${item.status}`,
        "",
      ].join("\n")
    ),
    "Puedes revisar estas facturas desde MisBolos.",
    "misbolos://",
    "",
    "Recibes este correo porque tienes activados los recordatorios de facturas en MisBolos.",
  ].join("\n");

  return { htmlContent, textContent };
}

async function logReminder(
  client: ReturnType<typeof createClient>,
  settings: UserSettings,
  recipient: string,
  subject: string,
  pending: PendingItem[],
  total: number,
  status: string,
  errorMessage?: string | null,
  sentAt?: string,
) {
  await client.from("invoice_reminder_email_logs").insert({
    user_id: settings.user_id,
    recipient_email: recipient,
    subject,
    invoice_ids: pending.map((item) => item.invoiceId ?? item.id),
    invoice_count: pending.length,
    total_pending: total,
    status,
    error_message: errorMessage,
    sent_at: sentAt ?? null,
  });
}

function parseSender(value: string) {
  const match = value.match(/^\s*(.*?)\s*<([^>]+)>\s*$/);
  if (match) return { name: match[1].trim(), email: match[2].trim() };
  return { email: value.trim() };
}

function formatCurrency(value: number) {
  return new Intl.NumberFormat("es-ES", { style: "currency", currency: "EUR" }).format(value);
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("es-ES", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(date);
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
