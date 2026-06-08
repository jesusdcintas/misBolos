/// <reference lib="deno.ns" />
// @deno-types="https://esm.sh/@supabase/supabase-js@2?dts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ ok: false, error: "Missing Authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json(
        {
          ok: false,
          error:
            "Missing SUPABASE_URL, SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY",
        },
        500,
      );
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
    });

    const {
      data: { user },
      error: userErr,
    } = await userClient.auth.getUser();

    if (userErr || !user) {
      return json({ ok: false, error: "Unauthorized" }, 401);
    }

    const uid = user.id;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Orden defensivo: primero dependientes, luego principales.
    // Si una tabla no existe en este proyecto, se ignora.
    const tables = [
      "invoice_reminder_email_logs",
      "invoice_fiscal_records",
      "invoice_email_logs",
      "invoice_number_changes",
      "sync_queue",
      "pending_deletions",
      "drive_sync_queue",
      "declared_quarters",
      "assets",
      "expenses",
      "invoices",
      "gigs",
      "clients",
      "user_settings",
    ];

    for (const table of tables) {
      const exists = await tableExists(admin, table);
      if (!exists) continue;

      const { error } = await admin.from(table).delete().eq("user_id", uid);
      if (error) {
        return json(
          {
            ok: false,
            error: `Error deleting from ${table}`,
            details: error.message,
          },
          500,
        );
      }
    }

    const { error: deleteUserError } = await admin.auth.admin.deleteUser(uid);
    if (deleteUserError) {
      return json(
        {
          ok: false,
          error: "Error deleting auth user",
          details: deleteUserError.message,
        },
        500,
      );
    }

    return json({ ok: true, success: true });
  } catch (error: unknown) {
    const details = error instanceof Error ? error.message : String(error);
    return json(
      { ok: false, error: "Unexpected error", details },
      500,
    );
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

async function tableExists(
  admin: ReturnType<typeof createClient>,
  table: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("information_schema.tables")
    .select("table_name")
    .eq("table_schema", "public")
    .eq("table_name", table)
    .limit(1);

  if (error) return false;
  return Array.isArray(data) && data.length > 0;
}
