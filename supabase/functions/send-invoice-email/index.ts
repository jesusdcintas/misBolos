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
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const fromEmail = Deno.env.get("INVOICE_FROM_EMAIL");

    if (!resendApiKey || !fromEmail) {
      return json({ ok: false, error: "Email provider is not configured" }, 500);
    }

    const body = (await req.json()) as SendInvoiceRequest;
    validate(body);

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [body.recipientEmail],
        subject: body.subject,
        html: `
          <p>Hola,</p>
          <p>Adjunto la factura #${body.invoiceNumber}.</p>
          <p>Gracias.</p>
        `,
        attachments: [
          {
            filename: body.fileName,
            content: body.pdfBase64,
          },
        ],
      }),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      return json(
        { ok: false, error: data?.message ?? "Email provider failed" },
        response.status,
      );
    }

    return json({ ok: true, provider: "resend", id: data?.id ?? null });
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

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
