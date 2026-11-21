import type { RequestHandler } from './$types';

type GatewayEnv = {
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
};

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FILENAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$/;
const JWT = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const FOLDERS = new Set(['providers', 'clients', '']);
const MAX_JWT_LENGTH = 4096;

const CONTENT_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'application/pdf'
]);

const SECURITY_HEADERS: Record<string, string> = {
  'Cache-Control': 'private, no-store',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Content-Security-Policy': "default-src 'none'; sandbox"
};

function erreur(status: number, code: string): Response {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: { 'Content-Type': 'application/json', ...SECURITY_HEADERS }
  });
}

export const GET: RequestHandler = async ({ params, url, request, platform }) => {
  const env = (platform?.env ?? {}) as unknown as GatewayEnv;
  const base = (env.SUPABASE_URL ?? '').replace(/\/+$/, '');
  const apikey = env.SUPABASE_ANON_KEY ?? '';
  if (!base || !apikey) return erreur(500, 'gateway_not_configured');

  // 1. Jeton de l'appelant (vérifié par Supabase lors de l'appel Storage).
  const auth = request.headers.get('authorization') ?? '';
  const jeton = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!jeton || jeton.length > MAX_JWT_LENGTH || !JWT.test(jeton)) {
    return erreur(401, 'unauthorized');
  }

  // 2. Paramètres validés : aucun fragment de chemin ne vient d'ailleurs.
  const owner = url.searchParams.get('owner') ?? '';
  const folder = url.searchParams.get('folder') ?? 'providers';
  const filename = params.filename ?? '';
  if (!UUID.test(owner) || !FOLDERS.has(folder) || !FILENAME.test(filename)) {
    return erreur(400, 'invalid_request');
  }

  const chemin = folder
    ? `${folder}/${owner.toLowerCase()}/${filename}`
    : `${owner.toLowerCase()}/${filename}`;

  // 3. Lecture avec les droits de l'appelant : la RLS du bucket « documents »
  //    n'autorise que le propriétaire du dossier et les administrateurs.
  let amont: Response;
  try {
    amont = await fetch(
      `${base}/storage/v1/object/authenticated/documents/${chemin}`,
      { headers: { apikey, Authorization: `Bearer ${jeton}` } }
    );
  } catch {
    return erreur(502, 'upstream_unreachable');
  }

  if (amont.status === 401) return erreur(401, 'unauthorized');
  if (!amont.ok || !amont.body) return erreur(404, 'not_found');

  const type = (amont.headers.get('content-type') ?? '').split(';')[0].trim();
  const headers = new Headers(SECURITY_HEADERS);
  headers.set(
    'Content-Type',
    CONTENT_TYPES.has(type) ? type : 'application/octet-stream'
  );
  headers.set('Content-Disposition', 'inline');
  const longueur = amont.headers.get('content-length');
  if (longueur) headers.set('Content-Length', longueur);

  return new Response(amont.body, { status: 200, headers });
};