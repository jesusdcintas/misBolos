import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type TaskType =
  | "chat"
  | "assistant_action"
  | "whatsapp"
  | "email"
  | "summarize";

type RequestBody = {
  task_type: string;
  message: string;
  context_data?: Record<string, unknown>;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MAX_MESSAGE = 6000;
const MAX_CONTEXT = 4000;
const MAX_CONTEXT_ASSISTANT = 1500;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !supabaseAnon) {
      return json({ ok: false, error: "Supabase config missing." }, 500);
    }

    const client = createClient(supabaseUrl, supabaseAnon, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const {
      data: { user },
      error: authError,
    } = await client.auth.getUser();

    if (authError || !user) {
      return json({ ok: false, error: "Unauthorized" }, 401);
    }

    const body = (await req.json()) as RequestBody;
    if (!body?.task_type || !body?.message?.trim()) {
      return json({ ok: false, error: "task_type y message son obligatorios" }, 400);
    }
    if (isLegacyExtractionTask(body.task_type)) {
      return json(
        {
          ok: false,
          error: "Tarea no soportada: la extracción de documentos se hace en local.",
        },
        400,
      );
    }
    if (!isAllowedTask(body.task_type)) {
      return json({ ok: false, error: "task_type no soportado" }, 400);
    }

    const provider = (Deno.env.get("AI_PROVIDER") ?? "groq").toLowerCase();
    if (provider !== "groq") {
      return json({ ok: false, error: "AI provider no soportado" }, 400);
    }

    const groqApiKey = Deno.env.get("GROQ_API_KEY");
    const textModel = Deno.env.get("GROQ_MODEL") ?? "llama-3.1-8b-instant";
    if (!groqApiKey) {
      return json({ ok: false, error: "GROQ_API_KEY no configurada" }, 500);
    }

    const message = truncate(body.message.trim(), MAX_MESSAGE);
    const contextLimit = body.task_type === "assistant_action"
      ? MAX_CONTEXT_ASSISTANT
      : MAX_CONTEXT;
    const contextData = truncateJson(body.context_data ?? {}, contextLimit);

    const isAssistantAction = body.task_type === "assistant_action";
    const model = textModel;
    const messages = buildMessages({
      task: body.task_type,
      message,
      context: contextData,
    });

    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${groqApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        temperature: isAssistantAction ? 0.1 : 0.4,
        max_tokens: isAssistantAction ? 1200 : 700,
        ...(isAssistantAction
          ? { response_format: { type: "json_object" } }
          : {}),
        messages,
      }),
    });

    const raw = await response.text();
    if (response.status === 429) {
      return json(
        {
          ok: false,
          code: "rate_limit",
          error: "Has alcanzado el límite gratuito temporal de IA. Inténtalo más tarde.",
        },
        429,
      );
    }
    if (!response.ok) {
      const upstreamError = extractUpstreamError(raw);
      console.error(
        `[groq-assistant] user=${user.id} task=${body.task_type} status=${response.status} upstream=${upstreamError}`,
      );
      return json(
        {
          ok: false,
          code: "upstream_error",
          error: "Error al consultar IA.",
          upstream_status: response.status,
          upstream_error: upstreamError,
        },
        502,
      );
    }

    const data = JSON.parse(raw);
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) {
      return json({ ok: false, error: "Respuesta vacía de IA." }, 502);
    }

    if (body.task_type === "assistant_action") {
      try {
        const action = normalizeAssistantAction(parseJsonContent(content));
        console.log(
          `[groq-assistant] assistant_action user=${user.id} action=${action.accion} payload=${JSON.stringify(action).slice(0, 3000)}`,
        );
        return json({ ok: true, task_type: body.task_type, model, action });
      } catch (_) {
        return json(
          {
            ok: false,
            error: "La IA no devolvió una acción válida. Puedes intentarlo con más detalle.",
          },
          502,
        );
      }
    }

    return json({ ok: true, task_type: body.task_type, model, text: content.trim() });
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
  }
});

function isAllowedTask(task: string): task is TaskType {
  return (
    task === "chat" ||
    task === "assistant_action" ||
    task === "whatsapp" ||
    task === "email" ||
    task === "summarize"
  );
}

function isLegacyExtractionTask(task: string) {
  return task === "extract_expense" || task === "extract_investment";
}

function extractUpstreamError(raw: string): string {
  if (!raw.trim()) return "empty upstream body";
  try {
    const parsed = JSON.parse(raw);
    if (isRecord(parsed)) {
      const errorObj = isRecord(parsed.error) ? parsed.error : null;
      if (errorObj) {
        const message = readString(errorObj.message);
        const code = readString(errorObj.code);
        const type = readString(errorObj.type);
        const parts = [type, code, message].filter(Boolean);
        if (parts.length > 0) return parts.join(" | ");
      }
      const message = readString(parsed.message);
      if (message) return message;
    }
  } catch (_) {
    // ignore parse error and return raw snippet
  }
  return raw.slice(0, 400);
}

function normalizeAssistantAction(input: unknown) {
  const source = isRecord(input) ? input : {};
  const accion = readString(source.accion);
  const allowed = new Set([
    "crear_bolos",
    "buscar_bolos",
    "actualizar_bolo",
    "crear_factura",
    "enviar_factura_email",
    "buscar_cliente",
    "crear_cliente",
    "crear_clientes",
    "resumen_agenda",
    "pregunta_aclaratoria",
    "no_soportado",
  ]);
  const normalizedAction = accion && allowed.has(accion)
    ? accion
    : "pregunta_aclaratoria";

  return {
    accion: normalizedAction,
    requiere_confirmacion:
      typeof source.requiere_confirmacion === "boolean"
        ? source.requiere_confirmacion
        : !["buscar_bolos", "buscar_cliente", "resumen_agenda", "pregunta_aclaratoria", "no_soportado"].includes(
            normalizedAction,
          ),
    confianza: clamp(readNumber(source.confianza) ?? 0.7, 0, 1),
    pregunta: readString(source.pregunta),
    respuesta: readString(source.respuesta),
    bolos: Array.isArray(source.bolos) ? source.bolos.filter(isRecord) : [],
    filtros: isRecord(source.filtros) ? source.filtros : {},
    objetivo: isRecord(source.objetivo) ? source.objetivo : {},
    cambios: isRecord(source.cambios) ? source.cambios : {},
    cliente: normalizeAssistantClient(source.cliente),
    clientes: normalizeAssistantClients(source.clientes),
    factura: isRecord(source.factura) ? source.factura : {},
    email: isRecord(source.email) ? source.email : {},
    advertencias: readWarnings(source.advertencias),
  };
}

function parseJsonContent(content: string) {
  const trimmed = content.trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  const clean = fenced ? fenced[1].trim() : trimmed;
  return JSON.parse(clean);
}

function normalizeAssistantClient(input: unknown) {
  const source = isRecord(input) ? input : {};
  return {
    nombre: readString(source.nombre) ?? "",
    alias_principal:
      readString(source.alias_principal) ??
      readString(source.alias) ??
      "",
    nombres_alternativos: readStringArray(
      source.nombres_alternativos ?? source.aliases,
    ),
    cif_nif:
      readString(source.cif_nif) ??
      readString(source.cifNif) ??
      readString(source.cif) ??
      readString(source.nif) ??
      "",
    direccion: readString(source.direccion) ?? "",
    ciudad: readString(source.ciudad) ?? "",
    codigo_postal:
      readString(source.codigo_postal) ??
      readString(source.codigoPostal) ??
      readString(source.cp) ??
      readString(source["c.p."]) ??
      "",
    provincia: readString(source.provincia) ?? "",
    email: readString(source.email) ?? "",
    telefono: readString(source.telefono) ?? "",
    telefono_whatsapp:
      readString(source.telefono_whatsapp) ??
      readString(source.whatsapp) ??
      readString(source.whatsapp_phone) ??
      "",
    notas: readString(source.notas) ?? "",
  };
}

function normalizeAssistantClients(input: unknown) {
  if (!Array.isArray(input)) return [];
  return input.map(normalizeAssistantClient);
}

function readString(value: unknown) {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text.length > 0 ? text : null;
}

function readNumber(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const normalized = value.replace(",", ".").trim();
  if (!normalized) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function readWarnings(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item).trim()).filter(Boolean);
}

function readStringArray(value: unknown) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item).trim()).filter(Boolean);
  }
  const text = readString(value);
  if (!text) return [];
  return text
    .split(/\n|,|;/)
    .map((item) => item.replace(/^[-*]\s*/, "").trim())
    .filter(Boolean);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function buildMessages({
  task,
  message,
  context,
}: {
  task: TaskType;
  message: string;
  context: Record<string, unknown>;
}) {
  const contextText = JSON.stringify(context);

  if (task === "assistant_action") {
    const assistantPrompt = [
      "Eres el intérprete operativo de MisBolos, una app para gestionar bolos, clientes, facturas y agenda.",
      "Tu única salida debe ser JSON válido. No escribas texto fuera del JSON.",
      "No ejecutes acciones y no afirmes que una acción se ha realizado. Solo interpreta intención.",
      "Acciones permitidas: crear_bolos, buscar_bolos, actualizar_bolo, crear_factura, enviar_factura_email, buscar_cliente, crear_cliente, crear_clientes, resumen_agenda, pregunta_aclaratoria, no_soportado.",
      "Formato base: {\"accion\":string,\"requiere_confirmacion\":boolean,\"confianza\":number,\"pregunta\":string|null,\"respuesta\":string|null,\"bolos\":array,\"filtros\":object,\"objetivo\":object,\"cambios\":object,\"cliente\":object,\"clientes\":array,\"factura\":object,\"email\":object,\"advertencias\":array}.",
      "Para crear_cliente, devuelve SIEMPRE cliente con este esquema exacto: {\"nombre\":\"\",\"alias_principal\":\"\",\"nombres_alternativos\":[],\"cif_nif\":\"\",\"direccion\":\"\",\"ciudad\":\"\",\"codigo_postal\":\"\",\"provincia\":\"\",\"email\":\"\",\"telefono\":\"\",\"telefono_whatsapp\":\"\",\"notas\":\"\"}.",
      "Si detectas varios clientes, usa SIEMPRE accion=crear_clientes y devuelve array clientes con un objeto por cliente usando el mismo esquema exacto. No mezcles varios clientes dentro de cliente único.",
      "Extrae TODOS los campos de cliente que el usuario proporcione. No te limites al nombre. Si un campo no aparece, usa cadena vacía o lista vacía.",
      "Detecta 'Alias principal' como alias_principal. Detecta listas o viñetas de 'Nombres alternativos' como array nombres_alternativos.",
      "Detecta CIF/NIF, CIF, NIF como cif_nif. Detecta 'C.P.', 'CP' y 'Código postal' como codigo_postal.",
      "Mantén formato limpio: sin etiquetas repetidas, sin saltos innecesarios, sin inventar datos.",
      "Para crear_bolos usa bolos con {\"fecha\":\"YYYY-MM-DD\",\"nombre\":string,\"importe\":number|null,\"facturable\":boolean,\"estado\":\"pendiente_gestion\",\"notas\":string|null}.",
      "Interpreta facturable como bolo oficial. Interpreta no facturable, en b o sin factura como facturable=false.",
      "Para actualizar_bolo usa este esquema: filtros {\"cliente_o_nombre\":\"\",\"fecha\":\"YYYY-MM-DD|null\",\"importe_actual\":number|null} y updates {\"fecha\":\"YYYY-MM-DD|null\",\"importe\":number|null,\"estado\":string|null,\"facturable\":boolean|null}.",
      "Si el usuario dice 'de 500€ a 400€', interpreta importe_actual=500 y updates.importe=400.",
      "Si el usuario no indica año, usa el año actual indicado en contexto. Resuelve fechas relativas con la fecha actual del contexto.",
      "Si falta una fecha concreta para crear o cambiar un bolo, devuelve accion=pregunta_aclaratoria y pregunta breve.",
      "Si hay ambigüedad importante, pregunta. No inventes clientes, emails, importes ni fechas.",
      "Para búsquedas usa filtros con fecha_desde y fecha_hasta cuando sea posible.",
      "Para búsquedas de facturas usa filtros compatibles con la app: status (borrador|pendiente_de_cobro|cobrada), mes (1-12), cliente (nombre o alias), fecha (YYYY-MM-DD).",
      "Mapea 'pendiente de cobro' a status='pendiente_de_cobro' y 'cobrada/pagada' a status='cobrada'.",
      "Para actualizar_bolo, crear_factura y enviar_factura_email, intenta rellenar objetivo con pistas estructuradas: cliente, cliente_nombre, nombre, gig_nombre, fecha, importe, numero_factura, selector, gig_id, invoice_id si existen.",
      "Si el usuario menciona varios bolos y no queda claro cuál modificar, usa accion=pregunta_aclaratoria con una pregunta breve.",
      "Para 'último bolo' usa objetivo {\"selector\":\"ultimo_bolo\"}. Para 'última factura' usa objetivo {\"selector\":\"ultima_factura\"}.",
      "Para marcar cobrado usa cambios {\"estado\":\"cobrado\"}. Para cambiar fecha usa cambios {\"fecha\":\"YYYY-MM-DD\"}.",
      "Para enviar email incluye email {\"destinatario\":string|null,\"asunto\":string|null,\"mensaje\":string|null}. Si falta destinatario, deja null.",
      "No incluyas fiscalidad avanzada.",
    ].join(" ");

    return [
      {
        role: "system",
        content: assistantPrompt,
      },
      {
        role: "user",
        content: `Contexto:\n${contextText}\nMensaje:\n${message}`,
      },
    ];
  }

  const systemByTask: Record<string, string> = {
    chat: "Eres un asistente breve y útil para una app de gestión de bolos y facturas.",
    whatsapp:
      "Redacta mensajes WhatsApp claros, cercanos y profesionales en español. Manténlos breves.",
    email:
      "Redacta emails profesionales en español, con asunto y cuerpo claros, tono cordial.",
    summarize:
      "Resume información de forma precisa, sin inventar datos. Usa español claro.",
  };

  return [
    { role: "system", content: systemByTask[task] },
    {
      role: "user",
      content: `Mensaje:\n${message}\nContexto mínimo:\n${contextText}`,
    },
  ];
}

function truncate(value: string, max: number) {
  if (value.length <= max) return value;
  return value.slice(0, max);
}

function truncateJson(value: Record<string, unknown>, maxLen: number) {
  const raw = JSON.stringify(value);
  if (raw.length <= maxLen) return value;
  return { truncated: true, preview: raw.slice(0, maxLen) };
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
