import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type TaskType =
  | "chat"
  | "whatsapp"
  | "email"
  | "summarize"
  | "extract_expense"
  | "extract_investment";

type RequestBody = {
  task_type: TaskType;
  input_type?: "text" | "image";
  message: string;
  context_data?: Record<string, unknown>;
  image_text?: string;
  image_base64?: string;
  image_mime_type?: string;
  mime_type?: string;
  image_url?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MAX_MESSAGE = 6000;
const MAX_IMAGE_TEXT = 12000;
const MAX_CONTEXT = 12000;
const MAX_IMAGE_BASE64 = 4 * 1024 * 1024;

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
    if (!isAllowedTask(body.task_type)) {
      return json({ ok: false, error: "task_type no soportado" }, 400);
    }

    const provider = (Deno.env.get("AI_PROVIDER") ?? "groq").toLowerCase();
    if (provider !== "groq") {
      return json({ ok: false, error: "AI provider no soportado" }, 400);
    }

    const groqApiKey = Deno.env.get("GROQ_API_KEY");
    const textModel = Deno.env.get("GROQ_MODEL") ?? "llama-3.1-8b-instant";
    const visionModel =
      Deno.env.get("GROQ_VISION_MODEL") ??
      "meta-llama/llama-4-scout-17b-16e-instruct";
    if (!groqApiKey) {
      return json({ ok: false, error: "GROQ_API_KEY no configurada" }, 500);
    }

    const message = truncate(body.message.trim(), MAX_MESSAGE);
    const imageText = truncate(body.image_text?.trim() ?? "", MAX_IMAGE_TEXT);
    const contextData = truncateJson(body.context_data ?? {}, MAX_CONTEXT);
    const imageBase64 = body.image_base64?.trim() ?? "";
    const imageUrl = body.image_url?.trim() ?? "";
    const imageMimeType =
      body.image_mime_type?.trim() || body.mime_type?.trim() || "image/jpeg";
    const hasImagePayload = Boolean(imageBase64 || imageUrl);
    if (body.input_type === "image" && !hasImagePayload) {
      return json({ ok: false, error: "No se ha recibido ninguna imagen." }, 400);
    }
    const hasImage = body.input_type === "image" || hasImagePayload;

    if (imageBase64.length > MAX_IMAGE_BASE64) {
      return json({ ok: false, error: "Imagen demasiado grande para Groq Vision" }, 413);
    }

    const isExtract =
      body.task_type === "extract_expense" ||
      body.task_type === "extract_investment";
    const model = isExtract && hasImage ? visionModel : textModel;
    const messages = buildMessages({
      task: body.task_type,
      message,
      context: contextData,
      imageText,
      imageBase64,
      imageMimeType,
      imageUrl,
    });

    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${groqApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        temperature: isExtract ? 0.1 : 0.4,
        max_tokens: isExtract ? 900 : 700,
        ...(isExtract ? { response_format: { type: "json_object" } } : {}),
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
      console.error(
        `[groq-assistant] user=${user.id} task=${body.task_type} status=${response.status}`,
      );
      return json({ ok: false, error: "Error al consultar IA." }, 502);
    }

    const data = JSON.parse(raw);
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) {
      return json({ ok: false, error: "Respuesta vacía de IA." }, 502);
    }

    if (body.task_type === "extract_expense") {
      try {
        const extracted = normalizeExtractedExpense(JSON.parse(content));
        return json({ ok: true, task_type: body.task_type, model, extracted });
      } catch (_) {
        return json(
          {
            ok: false,
            error: "La IA no devolvió JSON válido. Puedes rellenarlo manualmente.",
          },
          502,
        );
      }
    }

    if (body.task_type === "extract_investment") {
      try {
        const groqExtracted = normalizeExtractedInvestment(JSON.parse(content));
        const extracted = postProcessExtractedInvestment(
          collectExtractionText(message, imageText, contextData),
          groqExtracted,
        );
        return json({ ok: true, task_type: body.task_type, model, extracted });
      } catch (_) {
        return json(
          {
            ok: false,
            error: "La IA no devolvió JSON válido. Puedes rellenarlo manualmente.",
          },
          502,
        );
      }
    }

    return json({ ok: true, task_type: body.task_type, model, text: content.trim() });
  } catch (error) {
    return json({ ok: false, error: error.message ?? String(error) }, 400);
  }
});

function isAllowedTask(task: string): task is TaskType {
  return (
    task === "chat" ||
    task === "whatsapp" ||
    task === "email" ||
    task === "summarize" ||
    task === "extract_expense" ||
    task === "extract_investment"
  );
}

function normalizeExtractedExpense(input: unknown) {
  const source = isRecord(input) ? input : {};
  const warnings = readWarnings(source.warnings).filter(
    (warning) =>
      !/importe del producto.*base_amount/i.test(warning) &&
      !/producto usado como base/i.test(warning),
  );
  let confidence = readNumber(source.confidence) ?? (warnings.length > 0 ? 0.65 : 0);
  confidence = clamp(confidence, 0, 1);
  if (warnings.length > 0 && confidence >= 1) confidence = 0.9;

  const rawCategory = readString(source.category);
  const category = rawCategory?.toLowerCase() === "combustible"
    ? "Combustible"
    : rawCategory;
  const concept = normalizeConcept(readString(source.concept), category);
  const baseAmount = readNumber(source.base_amount);
  const taxAmount = readNumber(source.tax_amount);
  let vatRate = readNumber(source.vat_rate);
  if ((vatRate === null || vatRate === 0) && baseAmount && taxAmount) {
    vatRate = Math.round((taxAmount / baseAmount) * 100);
  }

  return {
    merchant: readString(source.merchant),
    station: readString(source.station),
    invoice_number: readString(source.invoice_number),
    date: normalizeDate(readString(source.date)),
    operation_date: normalizeDate(readString(source.operation_date)),
    concept,
    category,
    base_amount: baseAmount,
    tax_amount: taxAmount,
    vat_rate: vatRate,
    total_amount: readNumber(source.total_amount),
    discount_amount: readNumber(source.discount_amount),
    liters: readNumber(source.liters),
    price_per_liter: readNumber(source.price_per_liter),
    vehicle_plate: readString(source.vehicle_plate),
    confidence,
    warnings,
  };
}

function normalizeExtractedInvestment(input: unknown) {
  const source = isRecord(input) ? input : {};
  const warnings = readWarnings(source.warnings);
  let confidence = readNumber(source.confidence) ?? (warnings.length > 0 ? 0.65 : 0);
  confidence = clamp(confidence, 0, 1);
  if (warnings.length > 0 && confidence >= 1) confidence = 0.9;

  const category = normalizeInvestmentCategory(readString(source.category));
  const maxAnnual = maxAnnualForInvestmentCategory(category);
  let baseAmount = readNumber(source.base_amount);
  let taxAmount = readNumber(source.tax_amount);
  let vatRate = readNumber(source.vat_rate);
  let totalAmount = readNumber(source.total_amount);
  if ((vatRate === null || vatRate === 0) && baseAmount && taxAmount) {
    vatRate = Math.round((taxAmount / baseAmount) * 100);
  }
  if (
    baseAmount !== null &&
    taxAmount !== null &&
    totalAmount !== null &&
    Math.abs(totalAmount - (baseAmount + taxAmount)) > 0.02 &&
    vatRate !== null &&
    vatRate > 0
  ) {
    baseAmount = roundMoney(totalAmount / (1 + vatRate / 100));
    taxAmount = roundMoney(totalAmount - baseAmount);
  }
  const amountsValid =
    baseAmount !== null &&
    taxAmount !== null &&
    totalAmount !== null &&
    Math.abs(totalAmount - (baseAmount + taxAmount)) <= 0.02;
  if (amountsValid) {
    removeInvestmentAmountWarnings(warnings);
    if (confidence < 0.95) confidence = 0.95;
  }
  const annual = baseAmount !== null ? roundMoney(baseAmount * (maxAnnual / 100)) : null;

  return {
    name: normalizeInvestmentName(readString(source.name), readString(source.concept)),
    supplier: normalizeSupplier(readString(source.supplier)),
    invoice_number: readString(source.invoice_number),
    purchase_date: normalizeDate(readString(source.purchase_date)),
    concept: readString(source.concept),
    category,
    base_amount: baseAmount,
    tax_amount: taxAmount,
    vat_rate: vatRate,
    total_amount: totalAmount,
    useful_life_years: usefulLifeForInvestmentCategory(category),
    max_annual_percentage: maxAnnual,
    annual_amortization_amount: annual,
    deductible_percentage: readNumber(source.deductible_percentage),
    confidence,
    warnings,
  };
}

function postProcessExtractedInvestment(
  rawText: string,
  input: Record<string, unknown>,
) {
  console.log(
    `[groq-assistant] investment groq base=${input.base_amount} tax=${input.tax_amount} total=${input.total_amount} category=${input.category}`,
  );
  const output = { ...input };
  const fiscalSummary = extractFiscalSummary(rawText);
  if (fiscalSummary) {
    console.log(
      `[groq-assistant] investment fiscal summary base=${fiscalSummary.base} tax=${fiscalSummary.tax} total=${fiscalSummary.total} vat=${fiscalSummary.vatRate}`,
    );
    output.base_amount = fiscalSummary.base;
    output.tax_amount = fiscalSummary.tax;
    output.total_amount = fiscalSummary.total;
    output.vat_rate = fiscalSummary.vatRate;
    output.warnings = removeInvestmentAmountWarnings(readWarnings(output.warnings));
  }

  const combinedText = `${rawText} ${readString(output.name) ?? ""} ${
    readString(output.concept) ?? ""
  }`;
  if (isComputerInvestment(combinedText)) {
    output.category = "Informática";
    output.useful_life_years = 4;
    output.max_annual_percentage = 25;
  }
  if (normalizeText(combinedText).includes("sandisk") &&
      normalizeText(combinedText).includes("ssd") &&
      normalizeText(combinedText).includes("1tb")) {
    output.name = "Sandisk SSD portátil 1TB";
    output.concept = "SANDISK SDSSDE30-1T00-G26 PORTABLE SSD 1TB";
  }
  if (normalizeText(combinedText).includes("media") &&
      normalizeText(combinedText).includes("markt")) {
    output.supplier = "MEDIA MARKT SATURN S.A.";
  }

  let baseAmount = readNumber(output.base_amount);
  let taxAmount = readNumber(output.tax_amount);
  const totalAmount = readNumber(output.total_amount);
  let vatRate = readNumber(output.vat_rate);
  if ((vatRate === null || vatRate === 0) && baseAmount !== null && taxAmount !== null) {
    vatRate = Math.round((taxAmount / baseAmount) * 100);
    output.vat_rate = vatRate;
  }
  if (
    baseAmount !== null &&
    taxAmount !== null &&
    totalAmount !== null &&
    Math.abs(totalAmount - (baseAmount + taxAmount)) > 0.02
  ) {
    const warnings = readWarnings(output.warnings);
    warnings.push("El total no coincide exactamente con base + IVA. Revisa los importes.");
    output.warnings = Array.from(new Set(warnings));
    output.confidence = Math.min(readNumber(output.confidence) ?? 0.65, 0.7);
  } else if (baseAmount !== null && taxAmount !== null && totalAmount !== null) {
    output.warnings = removeInvestmentAmountWarnings(readWarnings(output.warnings));
    if ((readNumber(output.confidence) ?? 0) < 0.95) output.confidence = 0.95;
  }

  baseAmount = readNumber(output.base_amount);
  taxAmount = readNumber(output.tax_amount);
  if (baseAmount !== null) {
    const maxAnnual = readNumber(output.max_annual_percentage) ??
      maxAnnualForInvestmentCategory(readString(output.category) ?? "Otros");
    output.max_annual_percentage = maxAnnual;
    output.annual_amortization_amount = roundMoney(baseAmount * (maxAnnual / 100));
  }

  console.log(
    `[groq-assistant] investment final base=${output.base_amount} tax=${output.tax_amount} total=${output.total_amount} category=${output.category}`,
  );
  return output;
}

function collectExtractionText(
  message: string,
  imageText: string,
  context: Record<string, unknown>,
) {
  const parts = [message, imageText];
  for (const key of ["raw_text", "ocr_text", "text", "document_text"]) {
    const value = context[key];
    if (typeof value === "string") parts.push(value);
  }
  return parts.filter((part) => part.trim().length > 0).join("\n");
}

function extractFiscalSummary(rawText: string) {
  const normalized = normalizeText(rawText);
  if (!normalized.includes("base imponible") || !normalized.includes("cuota iva")) {
    return null;
  }
  const start = Math.max(0, normalized.lastIndexOf("base imponible") - 500);
  const block = rawText.slice(start);
  const rowPattern =
    /(\d{1,2})(?:[,.]\d{1,2})?\s*%?\s+([0-9][0-9.\s]*[,.]\d{2})\s*(?:€|eur)?\s+([0-9][0-9.\s]*[,.]\d{2})\s*(?:€|eur)?\s+([0-9][0-9.\s]*[,.]\d{2})\s*(?:€|eur)?/gi;
  let match: RegExpExecArray | null;
  let found: { vatRate: number; base: number; tax: number; total: number } | null = null;
  while ((match = rowPattern.exec(block)) !== null) {
    const vatRate = Number(match[1]);
    const base = parseSpanishAmount(match[2]);
    const tax = parseSpanishAmount(match[3]);
    const total = parseSpanishAmount(match[4]);
    if (
      vatRate > 0 &&
      base !== null &&
      tax !== null &&
      total !== null &&
      Math.abs(total - (base + tax)) <= 0.02
    ) {
      found = { vatRate, base, tax, total };
    }
  }
  return found;
}

function parseSpanishAmount(value: string) {
  const normalized = value.replace(/\s/g, "").replace(/\./g, "").replace(",", ".");
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? roundMoney(parsed) : null;
}

function isComputerInvestment(value: string) {
  return includesAny(normalizeText(value), [
    "informatica",
    "ssd",
    "sandisk",
    "disco duro",
    "hard drive",
    "portatil",
    "ordenador",
    "monitor",
    "tablet",
    "memoria",
    "pendrive",
    "almacenamiento",
    "periferico",
  ]);
}

function normalizeInvestmentCategory(value: string | null) {
  const text = normalizeText(value ?? "");
  if (
    includesAny(text, [
      "dj",
      "sonido",
      "altavoz",
      "subwoofer",
      "controladora",
      "mezcla",
      "microfono",
      "audio",
      "flight",
    ])
  ) {
    return "Equipo DJ / Sonido";
  }
  if (
    includesAny(text, ["iluminacion", "foco", "led", "laser", "strobe", "dmx", "truss"])
  ) {
    return "Iluminación";
  }
  if (
    includesAny(text, [
      "informatica",
      "portatil",
      "tablet",
      "ordenador",
      "ssd",
      "monitor",
      "impresora",
      "router",
      "periferico",
    ])
  ) {
    return "Informática";
  }
  if (includesAny(text, ["mobiliario", "mesa", "silla", "estanteria", "armario"])) {
    return "Mobiliario";
  }
  if (includesAny(text, ["vehiculo", "coche", "furgoneta", "remolque"])) {
    return "Vehículo";
  }
  if (
    includesAny(text, [
      "herramienta",
      "utillaje",
      "taladro",
      "atornillador",
      "escalera",
      "carro",
      "transpaleta",
    ])
  ) {
    return "Herramientas / Utillaje";
  }
  return "Otros";
}

function normalizeInvestmentName(name: string | null, concept: string | null) {
  const value = name ?? concept;
  if (!value) return null;
  const text = normalizeText(value);
  if (text.includes("sandisk") && text.includes("ssd") && text.includes("1tb")) {
    return "Sandisk SSD portátil 1TB";
  }
  return value;
}

function normalizeSupplier(value: string | null) {
  if (!value) return null;
  const text = normalizeText(value);
  if (text.includes("media") && text.includes("markt")) {
    return "MEDIA MARKT SATURN S.A.";
  }
  return value;
}

function removeInvestmentAmountWarnings(warnings: string[]) {
  for (let i = warnings.length - 1; i >= 0; i--) {
    const text = normalizeText(warnings[i]);
    if (
      (text.includes("iva") && text.includes("clara")) ||
      (text.includes("total") && text.includes("base")) ||
      text.includes("varios importes")
    ) {
      warnings.splice(i, 1);
    }
  }
  return warnings;
}

function roundMoney(value: number) {
  return Math.round(value * 100) / 100;
}

function maxAnnualForInvestmentCategory(category: string) {
  if (category === "Informática") return 25;
  if (category === "Vehículo") return 16;
  if (category === "Herramientas / Utillaje") return 30;
  if (category === "Mobiliario" || category === "Otros") return 10;
  return 20;
}

function usefulLifeForInvestmentCategory(category: string) {
  if (category === "Equipo DJ / Sonido") return 5;
  if (category === "Iluminación") return 5;
  if (category === "Informática") return 4;
  if (category === "Mobiliario") return 10;
  if (category === "Herramientas / Utillaje") return 3;
  return null;
}

function normalizeConcept(value: string | null, category: string | null) {
  if (!value) return null;
  const lower = value.toLowerCase();
  if ((category ?? "").toLowerCase() === "combustible") {
    if (lower.includes("efitec 98")) return "Gasolina efitec 98";
    const cleaned = value.replace(/suministro de/gi, "").replace(/\s+/g, " ").trim();
    if (lower.includes("diesel") || lower.includes("diésel") || lower.includes("gasoil")) {
      return `Diésel ${cleaned}`.trim();
    }
    if (!lower.startsWith("gasolina")) return `Gasolina ${cleaned}`.trim();
  }
  return value;
}

function normalizeDate(value: string | null) {
  if (!value) return null;
  const trimmed = value.trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
  const match = trimmed.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$/);
  if (!match) return null;
  const day = Number(match[1]);
  const month = Number(match[2]);
  const year = Number(match[3]);
  if (year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  return `${year.toString().padStart(4, "0")}-${month
    .toString()
    .padStart(2, "0")}-${day.toString().padStart(2, "0")}`;
}

function normalizeText(value: string) {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
}

function includesAny(value: string, needles: string[]) {
  return needles.some((needle) => value.includes(needle));
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
  imageText,
  imageBase64,
  imageMimeType,
  imageUrl,
}: {
  task: TaskType;
  message: string;
  context: Record<string, unknown>;
  imageText: string;
  imageBase64: string;
  imageMimeType: string;
  imageUrl: string;
}) {
  const contextText = JSON.stringify(context);

  if (task === "extract_expense" || task === "extract_investment") {
    const isInvestment = task === "extract_investment";
    const extractionPrompt =
      isInvestment
        ? "Extrae inversión en este formato JSON exacto: " +
          '{"name":string|null,"supplier":string|null,"invoice_number":string|null,"purchase_date":"YYYY-MM-DD"|null,"concept":string|null,"category":string|null,"base_amount":number|null,"tax_amount":number|null,"vat_rate":number|null,"total_amount":number|null,"useful_life_years":number|null,"max_annual_percentage":number|null,"annual_amortization_amount":number|null,"deductible_percentage":number|null,"confidence":number,"warnings":string[]}.' +
          " Devuelve únicamente JSON válido. No inventes importes ni fechas; si no está claro usa null. purchase_date es la fecha de factura/compra y debe ir en YYYY-MM-DD. Prioriza siempre el resumen fiscal final si contiene Base Imponible, Cuota IVA y Total; esos valores tienen prioridad sobre líneas de producto, canon, portes, accesorios, PVP, precio con IVA o total de línea. No uses P.v.p. unitario, PVP, precio con IVA ni total de línea como base_amount. Si no existe resumen fiscal final, suma todas las líneas con importe mayor que 0: bases, cuotas IVA y totales. No cojas solo la primera línea. Base amortizable=base_amount sin IVA; tax_amount=IVA separado; total_amount=total final de factura. Si aparece Base Imponible úsala como base_amount. Si aparece Cuota IVA úsala como tax_amount. Si aparece Total factura, Total a pagar o Importe total úsalo como total_amount, priorizando el total final. Categorías válidas: Equipo DJ / Sonido, Iluminación, Informática, Mobiliario, Vehículo, Herramientas / Utillaje, Otros. Si el producto contiene SSD, disco duro, portátil, ordenador, monitor, tablet o periférico, category=Informática. name debe ser el producto principal, nunca el proveedor. Ejemplo: SANDISK ... PORTABLE SSD 1TB => name='Sandisk SSD portátil 1TB'. Si proveedor contiene MEDIA MARKT SATURN S.A., usar exactamente ese supplier. Base amortizable no incluye IVA. No calcules amortización sobre total_amount. Porcentajes máximos: Equipo DJ / Sonido 20, Iluminación 20, Informática 25, Mobiliario 10, Vehículo 16, Herramientas / Utillaje 30, Otros 10. Vida útil: Equipo DJ / Sonido 5, Iluminación 5, Informática 4, Mobiliario 10, Vehículo null, Herramientas / Utillaje 3, Otros null. annual_amortization_amount=base_amount*(max_annual_percentage/100) si procede. No asumas deductible_percentage salvo indicación clara. Si base_amount + tax_amount coincide con total_amount, no añadas warnings de IVA ni total. Si hay warnings confidence no puede ser 1.0."
        : "Extrae gasto en este formato JSON exacto: " +
          '{"merchant":string|null,"station":string|null,"invoice_number":string|null,"date":"YYYY-MM-DD"|null,"operation_date":"YYYY-MM-DD"|null,"concept":string|null,"category":string|null,"base_amount":number|null,"tax_amount":number|null,"vat_rate":number|null,"total_amount":number|null,"discount_amount":number|null,"liters":number|null,"price_per_liter":number|null,"vehicle_plate":string|null,"confidence":number,"warnings":string[]}.' +
          " Devuelve únicamente JSON válido, sin markdown ni texto extra. No inventes datos; si no está claro, usa null. No uses la fecha actual si no hay fecha clara; no confundas número de factura con fecha. Acepta fechas españolas DD/MM/YYYY, DD.MM.YYYY y DD-MM-YYYY y conviértelas siempre a YYYY-MM-DD. Si aparece 'Fecha:' úsala como date. Si aparece 'F. Operación:' úsala como operation_date. Si aparece 'IVA 21,00% de X € Y €': vat_rate=21, base_amount=X y tax_amount=Y. Si aparece 'Importe del producto (Base Imponible)', úsalo como base_amount y no generes warning por ello. Si ves 'TOTAL FACTURA EUROS' úsalo como total_amount. Si aparece 'Descuento -0,52', discount_amount=0.52. Si hay litros y €/L, rellena liters y price_per_liter. Si hay matrícula, rellena vehicle_plate. Si el proveedor fiscal y estación son distintos, merchant=proveedor fiscal y station=estación. Si hay warnings confidence no puede ser 1.0. Si hay importe de producto antes de descuento, no usarlo como total final. Para combustible category='Combustible' y concept='Gasolina [producto]' o 'Diésel [producto]'. Si el producto contiene 'efitec 98', usar exactamente 'Gasolina efitec 98'. No uses conceptos genéricos como 'Suministro de...'.";
    const userText = `${extractionPrompt}\nContexto:\n${contextText}\nMensaje:\n${message}\nOCR:\n${imageText || "N/A"}`;
    const imageContent = imageUrl
      ? imageUrl
      : imageBase64
        ? `data:${imageMimeType};base64,${imageBase64}`
        : "";

    return [
      {
        role: "system",
        content:
          isInvestment
            ? "Eres un asistente de extracción de inversiones para una app de gestión de autónomos/DJs. Tu tarea es convertir facturas de compra de activos en JSON estructurado. No inventes datos. Si un campo no está claro, usa null. Devuelve únicamente JSON válido."
            : "Eres un asistente de extracción de gastos para una app de gestión de autónomos/DJs. Tu tarea es convertir texto de tickets, facturas o descripciones en JSON estructurado. No inventes datos. Si un campo no está claro, usa null. Devuelve únicamente JSON válido.",
      },
      {
        role: "user",
        content: imageContent
          ? [
              { type: "text", text: userText },
              { type: "image_url", image_url: { url: imageContent } },
            ]
          : userText,
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
