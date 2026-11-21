import { createClient, SupabaseClient, User } from "npm:@supabase/supabase-js@2";

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("supabase_env_missing");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** Valide le JWT Supabase de l'appelant et retourne l'utilisateur, ou null. */
export async function authenticatedUser(req: Request, db: SupabaseClient): Promise<User | null> {
  const header = req.headers.get("Authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const { data, error } = await db.auth.getUser(header.slice(7));
  return error || !data.user ? null : data.user;
}