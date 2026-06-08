type SendInvoiceRequest = {
  invoiceId: string;
  invoiceNumber: number;
  clientId: string;
  recipientEmail: string;
  subject: string;
  fileName: string;
  pdfBase64: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const brevoApiKey = Deno.env.get("BREVO_API_KEY");
    const fromEmail =
      Deno.env.get("INVOICE_FROM_EMAIL") ?? Deno.env.get("EMAIL_FROM");

    if (!brevoApiKey || !fromEmail) {
      return json({ ok: false, error: "Email provider is not configured" }, 500);
    }

    const body = (await req.json()) as SendInvoiceRequest;
    validate(body);

    if (!body.pdfBase64 || body.pdfBase64.trim().isEmpty) {
      return json({ ok: false, error: "PDF is empty" }, 400);
    }

    const sender = parseSender(fromEmail);

    const response = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        "api-key": brevoApiKey,
        accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        sender,
        to: [{ email: body.recipientEmail }],
        subject: body.subject,
        htmlContent: `
          <p>Hola,</p>
          <p>Adjunto la factura #${body.invoiceNumber}.</p>
          <p>Gracias.</p>
        `,
        // Brevo expects `attachment` (singular), not `attachments`.
        attachment: [
          {
            name: body.fileName,
            content: body.pdfBase64,
          },
        ],
      }),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      return json(
        { ok: false, error: data?.message ?? data?.code ?? "Email provider failed" },
        response.status,
      );
    }

    return json({ ok: true, provider: "brevo", id: data?.messageId ?? null });
  } catch (error) {
    return json({ ok: false, error: error.message ?? String(error) }, 400);
  }
});

function validate(body: SendInvoiceRequest) {
  if (!body.invoiceId) throw new Error("invoiceId is required");
  if (!body.clientId) throw new Error("clientId is required");
  if (!body.recipientEmail) throw new Error("recipientEmail is required");
  if (!body.subject) throw new Error("subject is required");
  if (!body.fileName) throw new Error("fileName is required");
  if (!body.pdfBase64) throw new Error("pdfBase64 is required");
}

function parseSender(value: string) {
  const match = value.match(/^\s*(.*?)\s*<([^>]+)>\s*$/);
  if (match) {
    return { name: match[1].trim(), email: match[2].trim() };
  }

  return { email: value.trim() };
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
