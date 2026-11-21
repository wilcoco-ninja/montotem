// Envoie une notification push FCM pour chaque ligne insérée dans public.notifications.
import { createClient } from "npm:@supabase/supabase-js@2";

type NotificationRow = {
  id: string;
  recipient_id: string | null;
  admins_only: boolean;
  type: string;
  title: string;
  body: string | null;
  payload: Record<string, unknown> | null;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const SA = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}") as ServiceAccount;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const enc = new TextEncoder();

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? enc.encode(input) : new Uint8Array(input);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function sameSecret(a: string, b: string): boolean {
  if (a.length === 0 || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

let cached: { token: string; exp: number } | null = null;

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;

  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: SA.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const key = await importKey(SA.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(`${header}.${claim}`),
  );
  const jwt = `${header}.${claim}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`oauth ${res.status}`);
  const json = await res.json();
  cached = { token: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cached.token;
}

async function envoyer(
  token: string,
  n: NotificationRow,
  auth: string,
): Promise<"ok" | "invalide" | "erreur"> {
  // FCM exige des valeurs de type texte dans « data ».
  const data: Record<string, string> = { type: n.type, notification_id: n.id };
  for (const [k, v] of Object.entries(n.payload ?? {})) {
    if (v !== null && v !== undefined) {
      data[k] = typeof v === "string" ? v : JSON.stringify(v);
    }
  }

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${SA.project_id}/messages:send`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${auth}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: n.title, body: n.body ?? "" },
          data,
          android: {
            priority: "HIGH",
            notification: { channel_id: "montotem_default" },
          },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    },
  );

  if (res.ok) return "ok";
  const err = await res.json().catch(() => ({}));
  const code = err?.error?.details?.[0]?.errorCode ?? err?.error?.status;
  // Seuls les jetons réellement périmés sont supprimés.
  if (res.status === 404 || code === "UNREGISTERED") return "invalide";
  console.error("FCM", res.status, JSON.stringify(err));
  return "erreur";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!sameSecret(req.headers.get("x-webhook-secret") ?? "", SECRET)) {
    return new Response("Unauthorized", { status: 401 });
  }

  let rec: NotificationRow;
  try {
    const body = await req.json();
    rec = (body.record ?? body) as NotificationRow;
  } catch {
    return new Response("Bad request", { status: 400 });
  }
  if (!rec?.id || !rec.title) return new Response("Bad request", { status: 400 });

  let userIds: string[] = [];
  if (rec.admins_only) {
    const { data } = await supabase.from("profiles").select("id").eq("role", "admin");
    userIds = (data ?? []).map((r: { id: string }) => r.id);
  } else if (rec.recipient_id) {
    userIds = [rec.recipient_id];
  }
  if (userIds.length === 0) return Response.json({ sent: 0 });

  const { data: rows } = await supabase
    .from("device_tokens")
    .select("token")
    .in("user_id", userIds);
  const tokens = [...new Set((rows ?? []).map((r: { token: string }) => r.token))];
  if (tokens.length === 0) return Response.json({ sent: 0 });

  const auth = await accessToken();
  const results = await Promise.all(tokens.map((t) => envoyer(t, rec, auth)));

  const invalides = tokens.filter((_, i) => results[i] === "invalide");
  if (invalides.length > 0) {
    await supabase.from("device_tokens").delete().in("token", invalides);
  }

  return Response.json({
    sent: results.filter((r) => r === "ok").length,
    removed: invalides.length,
  });
});