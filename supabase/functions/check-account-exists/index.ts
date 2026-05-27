import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type RequestBody = { email?: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      return json({ ok: false, error: "Missing Supabase env vars" }, 500);
    }

    const body = (await req.json().catch(() => ({}))) as RequestBody;
    const email = (body.email ?? "").trim().toLowerCase();
    if (!email) {
      return json({ ok: false, error: "email is required" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    let page = 1;
    const perPage = 200;
    let exists = false;

    while (true) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
      if (error) {
        return json({ ok: false, error: error.message }, 500);
      }

      const users = data?.users ?? [];
      if (users.some((u) => (u.email ?? "").toLowerCase() == email)) {
        exists = true;
        break;
      }

      if (users.length < perPage) break;
      page += 1;
      if (page > 50) break;
    }

    return json({ ok: true, exists });
  } catch (error) {
    return json({ ok: false, error: String(error) }, 500);
  }
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
