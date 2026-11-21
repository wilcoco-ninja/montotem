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

type SendResult = "sent" | "invalid" | "failed";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";

// Identique au canal créé dans PushService (Flutter).
const ANDROID_CHANNEL_ID = "montotem_default";
const MAX_TOKENS = 500;
const BATCH_SIZE = 20;
const SECRET_TTL_MS = 60_000;
const MAX_BEARER_LENGTH = 256;

const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const encoder = new TextEncoder();

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function safeEqual(a: string, b: string): boolean {
  const x = encoder.encode(a);
  const y = encoder.encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

// INTERNAL_PUSH_SECRET est lu dans internal_settings avec le rôle service_role.
// Mis en cache 60 s pour qu'un appelant non authentifié ne puisse pas
// multiplier les lectures en base.
let cachedSecret: { value: string; expiresAt: number } | null = null;

async function getInternalSecret(): Promise<string> {
  const now = Date.now();
  if (cachedSecret && cachedSecret.expiresAt > now) return cachedSecret.value;

  const { data, error } = await db
    .from("internal_settings")
    .select("value")
    .eq("key", "INTERNAL_PUSH_SECRET")
    .maybeSingle();
  if (error || !data) return "";

  cachedSecret = { value: String(data.value), expiresAt: now + SECRET_TTL_MS };
  return cachedSecret.value;
}

function base64Url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? encoder.encode(data) : data;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out.buffer;
}

let cachedToken: { value: string; expiresAt: number } | null = null;

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(unsigned)),
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64Url(signature)}`,
    }),
  });
  if (!res.ok) {
    throw new Error(`OAuth FCM ${res.status}: ${await res.text()}`);
  }
  const data = await res.json();
  cachedToken = {
    value: String(data.access_token),
    expiresAt: now + Number(data.expires_in ?? 3600),
  };
  return cachedToken.value;
}

async function adminUserIds(): Promise<string[]> {
  const [profiles, roles] = await Promise.all([
    db.from("profiles").select("id").eq("role", "admin"),
    db.from("admin_roles").select("user_id"),
  ]);
  if (profiles.error) throw profiles.error;
  if (roles.error) throw roles.error;
  const ids = new Set<string>();
  for (const row of profiles.data ?? []) ids.add(String(row.id));
  for (const row of roles.data ?? []) ids.add(String(row.user_id));
  return [...ids];
}

async function targetTokens(n: NotificationRow): Promise<string[]> {
  let userIds: string[];
  if (n.admins_only) {
    userIds = await adminUserIds();
  } else if (n.recipient_id) {
    userIds = [n.recipient_id];
  } else {
    return [];
  }
  if (userIds.length === 0) return [];

  const { data, error } = await db
    .from("device_tokens")
    .select("token")
    .in("user_id", userIds)
    .limit(MAX_TOKENS);
  if (error) throw error;
  return (data ?? []).map((row) => String(row.token));
}

// FCM n'accepte que des valeurs texte dans `data`.
function buildData(n: NotificationRow): Record<string, string> {
  const data: Record<string, string> = { type: n.type, notification_id: n.id };
  for (const [key, value] of Object.entries(n.payload ?? {})) {
    if (value === null || value === undefined) continue;
    data[key] = typeof value === "string" ? value : JSON.stringify(value);
  }
  return data;
}

async function sendOne(
  accessToken: string,
  projectId: string,
  token: string,
  n: NotificationRow,
  data: Record<string, string>,
): Promise<SendResult> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: n.title, body: n.body ?? "" },
          data,
          android: {
            priority: "HIGH",
            notification: { channel_id: ANDROID_CHANNEL_ID },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );
  if (res.ok) return "sent";

  const text = await res.text();
  if (
    res.status === 404 ||
    text.includes("UNREGISTERED") ||
    text.includes("not a valid FCM registration token")
  ) {
    return "invalid";
  }
  console.error(`FCM ${res.status}: ${text}`);
  return "failed";
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const auth = req.headers.get("Authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (bearer.length === 0 || bearer.length > MAX_BEARER_LENGTH) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  const expected = await getInternalSecret();
  if (!expected || !safeEqual(bearer, expected)) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // Seul l'identifiant est lu dans la requête : le contenu vient de la base.
  let notificationId = "";
  try {
    const body = await req.json();
    notificationId = String(body?.notification_id ?? "");
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(notificationId)) {
    return jsonResponse({ error: "invalid_id" }, 400);
  }

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(FCM_SERVICE_ACCOUNT) as ServiceAccount;
    if (!sa.project_id || !sa.client_email || !sa.private_key) {
      throw new Error("incomplete");
    }
  } catch {
    return jsonResponse({ error: "fcm_not_configured" }, 500);
  }

  try {
    const { data: notification, error } = await db
      .from("notifications")
      .select("id, recipient_id, admins_only, type, title, body, payload")
      .eq("id", notificationId)
      .maybeSingle();
    if (error) throw error;
    if (!notification) return jsonResponse({ error: "not_found" }, 404);

    const n = notification as NotificationRow;
    const tokens = await targetTokens(n);
    if (tokens.length === 0) {
      return jsonResponse({ sent: 0, invalid: 0, failed: 0, tokens: 0 });
    }

    const accessToken = await getAccessToken(sa);
    const data = buildData(n);
    const invalid: string[] = [];
    let sent = 0;
    let failed = 0;

    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const batch = tokens.slice(i, i + BATCH_SIZE);
      const results = await Promise.all(
        batch.map((token) => sendOne(accessToken, sa.project_id, token, n, data)),
      );
      results.forEach((result, index) => {
        if (result === "sent") sent++;
        else if (result === "invalid") invalid.push(batch[index]);
        else failed++;
      });
    }

    // Nettoyage : jetons FCM obsolètes (UNREGISTERED) retirés de device_tokens.
    if (invalid.length > 0) {
      await db.from("device_tokens").delete().in("token", invalid);
    }

    return jsonResponse({
      sent,
      invalid: invalid.length,
      failed,
      tokens: tokens.length,
    });
  } catch (e) {
    console.error("send-push", e);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});