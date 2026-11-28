-- ============================================================================
-- MonTotem — F-29 : DOCUMENTS PRIVÉS — FIN DES URL SIGNÉES LONGUE DURÉE
-- ============================================================================
-- Audit de sécurité (règle absolue : durée de vie des URL signées courte,
-- 5 à 15 minutes maximum, jamais de longue durée par défaut) :
--
--   Avant : uploaderDocument() générait pour le bucket privé « documents »
--   une URL signée valable 1 AN, stockée en base (photo_cni_url,
--   photo_cni_back_url). Un tel lien est un sésame permanent vers des pièces
--   d'identité : s'il fuit (log, capture, export), le document est exposé
--   pendant un an, indépendamment des droits.
--
--   Après : la base ne contient plus que des CHEMINS Storage. L'URL signée
--   (15 minutes maximum) est générée à la demande, à l'affichage, par un
--   appelant autorisé par la RLS (propriétaire ou admin — policies
--   storage_documents_select de la migration 051).
--
-- Ce script convertit les anciennes URL (dossiers d'avant la correction Dart)
-- en chemins. Idempotent. Exécution : Supabase SQL Editor.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Recto : URL signée → chemin Storage
--    Format ancien : https://<projet>.supabase.co/storage/v1/object/sign/
--                    documents/<chemin>?token=...
--    On retire la chaîne de requête puis le préfixe de signature.
-- ---------------------------------------------------------------------------
update public.providers
   set photo_cni_url = regexp_replace(
         split_part(photo_cni_url, '?', 1),
         '^/storage/v1/object/sign/documents/', '')
 where photo_cni_url like '%/object/sign/documents/%';

-- ---------------------------------------------------------------------------
-- 2. Verso : URL signée → chemin Storage
-- ---------------------------------------------------------------------------
update public.providers
   set photo_cni_back_url = regexp_replace(
         split_part(photo_cni_back_url, '?', 1),
         '^/storage/v1/object/sign/documents/', '')
 where photo_cni_back_url like '%/object/sign/documents/%';

commit;

-- ── Contrôles (à exécuter après le script) ──────────────────────────────────
-- select id, photo_cni_url, photo_cni_back_url from public.providers
--  where photo_cni_url like '%token=%' or photo_cni_back_url like '%token=%';
--   attendu : 0 ligne.
-- select id, photo_cni_url from public.providers where photo_cni_url is not null limit 5;
--   attendu : des chemins du type providers/<uid>/<timestamp>_document_recto.jpg
--   (ou des anciennes URL http pour les avatars, ce qui est normal).
