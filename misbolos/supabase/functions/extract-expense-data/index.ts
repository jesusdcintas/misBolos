type ExtractExpenseRequest = {
  file_name: string;
  mime_type: string;
  base64_data: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const DEFAULT_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const groqApiKey = Deno.env.get("GROQ_API_KEY");
    const model = Deno.env.get("GROQ_MODEL") ?? DEFAULT_MODEL;
    if (!groqApiKey) {
      return json(
        {
          ok: false,
          error:
            "GROQ_API_KEY no configurada en Supabase secrets para extracción IA.",
        },
        500,
      );
    }

    const body = (await req.json()) as ExtractExpenseRequest;
    validate(body);

    const dataUrl = `data:${body.mime_type};base64,${body.base64_data}`;
    const payload = {
      model,
      temperature: 0.1,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content:
            "Extrae datos de justificantes de gasto para una app española. Responde solo JSON válido.",
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text:
                "Devuelve este JSON exacto con null si no lo sabes: " +
                '{"concepto":string|null,"proveedor":string|null,"fecha":"YYYY-MM-DD"|null,"importe_base":number|null,"iva_rate":number|null,"categoria":"transporte|equipo|software|dietas|publicidad|formacion|otros"|null,"notas":string|null,"confidence":number,"warnings":string[]}. ' +
                "Asume EUR. Si detectas total e IVA pero no base, calcula base = total/(1+iva_rate/100).",
            },
            {
              type: "image_url",
              image_url: { url: dataUrl },
            },
          ],
        },
      ],
    };

    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${groqApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const raw = await response.text();
    if (!response.ok) {
      return json(
        {
          ok: false,
          error: `Groq error (${response.status}): ${raw.slice(0, 300)}`,
        },
        502,
      );
    }

    const data = JSON.parse(raw);
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) {
      return json({ ok: false, error: "Groq no devolvió contenido útil." }, 502);
    }

    let extracted: Record<string, unknown>;
    try {
      extracted = JSON.parse(content);
    } catch (_) {
      return json(
        {
          ok: false,
          error:
            "No se pudo interpretar la respuesta IA como JSON. Prueba con una foto más nítida.",
        },
        502,
      );
    }

    return json({ ok: true, extracted, model, file_name: body.file_name });
  } catch (error) {
    return json({ ok: false, error: error.message ?? String(error) }, 400);
  }
});

function validate(body: ExtractExpenseRequest) {
  if (!body.file_name) throw new Error("file_name es obligatorio");
  if (!body.mime_type) throw new Error("mime_type es obligatorio");
  if (!body.base64_data) throw new Error("base64_data es obligatorio");
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
