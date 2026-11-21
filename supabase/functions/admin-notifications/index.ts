import { createClient } from "npm:@supabase/supabase-js@2";
import { jwtVerify } from "npm:jose@5";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("supabase_env_missing");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** L'admin s'authentifie avec le JWT Django (SimpleJWT) : signature + expiration vérifiées. */
async function isAdmin(req: Request): Promise<boolean> {
  const header = req.headers.get("Authorization");
  const secret = Deno.env.get("ADMIN_JWT_SECRET");
  if (!header?.startsWith("Bearer ") || !secret) return false;
  try {
    await jwtVerify(header.slice(7), new TextEncoder().encode(secret), {
      algorithms: [Deno.env.get("ADMIN_JWT_ALG") ?? "HS256"],
    });
    return true;
  } catch {
    return false;
  }
}

async function unreadCount(db: ReturnType<typeof serviceClient>): Promise<number> {
  const { count } = await db
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("admins_only", true)
    .is("read_at", null);
  return count ?? 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!(await isAdmin(req))) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_request" }, 400);
  }
  const action = typeof body.action === "string" ? body.action : "";
  const db = serviceClient();

  if (action === "list") {
    const limit = Math.min(Math.max(Number(body.limit ?? 50) || 50, 1), 200);
    let query = db
      .from("notifications")
      .select("id, type, title, body, payload, created_at, read_at")
      .eq("admins_only", true)
      .order("created_at", { ascending: false })
      .limit(limit);
    if (body.unread_only === true) query = query.is("read_at", null);

    const { data, error } = await query;
    if (error) {
      console.error("admin-notifications: list", error);
      return json({ error: "internal_error" }, 500);
    }
    return json({ items: data ?? [], unread_count: await unreadCount(db) });
  }

  if (action === "mark_read") {
    const ids = Array.isArray(body.ids)
      ? body.ids.filter((v): v is string => typeof v === "string" && UUID.test(v))
      : [];
    if (ids.length === 0 || ids.length > 100) return json({ error: "invalid_request" }, 400);

    const { error } = await db
      .from("notifications")
      .update({ read_at: new Date().toISOString() })
      .eq("admins_only", true)
      .in("id", ids)
      .is("read_at", null);
    if (error) {
      console.error("admin-notifications: mark_read", error);
      return json({ error: "internal_error" }, 500);
    }
    return json({ ok: true, unread_count: await unreadCount(db) });
  }

  if (action === "mark_all_read") {
    const { error } = await db
      .from("notifications")
      .update({ read_at: new Date().toISOString() })
      .eq("admins_only", true)
      .is("read_at", null);
    if (error) {
      console.error("admin-notifications: mark_all_read", error);
      return json({ error: "internal_error" }, 500);
    }
    return json({ ok: true, unread_count: 0 });
  }

  return json({ error: "unknown_action" }, 400);
});