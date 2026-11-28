-- ============================================================================
-- MonTotem — F-28 : VERROU ANTI-ESCALADE DE PRIVILÈGES SUR PROFILES
-- ============================================================================
-- Audit de sécurité — faille CRITIQUE corrigée :
--   La policy RLS profiles_update_own (migration 050) autorise un utilisateur
--   à mettre à jour SA propre ligne SANS restriction de colonnes. Un client
--   malveillant pouvait donc exécuter :
--       PATCH /rest/v1/profiles?id=eq.<son-uid>  avec corps { role : admin }
--   et devenir administrateur (is_admin() lit profiles.role), avec accès à
--   toutes les policies admin, aux RPC admin et au journal d'audit.
--
-- Double protection mise en place :
--   1. GRANT de mise à jour par COLONNES : un utilisateur authentifié ne peut
--      plus écrire role, is_suspended, star_points, id, created_at, updated_at.
--      Les fonctions security definer (depenser_etoiles, etc.) ne sont pas
--      touchées : elles s'exécutent en tant que propriétaire (postgres).
--      Le rôle service_role (webhooks, Edge Functions) n'est pas affecté.
--   2. Déclencheur garde-fou (défense en profondeur) : si les grants étaient
--      ré-élargis un jour, le déclencheur bloque toute modification de
--      role / is_suspended / star_points par un client non admin.
--      Un admin légitime garde le droit de modifier CES champs pour les
--      AUTRES comptes (jamais les siens — il passera par le SQL Editor).
--
-- Idempotent. Exécution : Supabase SQL Editor.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Mise à jour par colonnes (protection principale)
-- ---------------------------------------------------------------------------
revoke update on public.profiles from authenticated, anon;

grant update (first_name, last_name, phone, email, photo_profil_url,
              inscription_complete, country_code)
  on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Déclencheur garde-fou (défense en profondeur)
-- ---------------------------------------------------------------------------
create or replace function public.profiles_verrou_champs_sensibles()
returns trigger
language plpgsql
security definer
set search_path = public
as $func$
begin
  -- Migrations, SQL Editor et fonctions security definer : elles s'exécutent
  -- sous le propriétaire (postgres / service_role), jamais sous le rôle
  -- 'authenticated'. Elles passent toujours.
  if current_user <> 'authenticated' then
    return new;
  end if;

  -- Un admin légitime peut modifier ces champs pour les AUTRES comptes.
  if public.is_admin() and old.id <> auth.uid() then
    return new;
  end if;

  -- Un utilisateur NON admin ne peut JAMAIS changer son propre rôle,
  -- son statut de suspension ni ses points d'étoiles.
  if to_jsonb(new) ->> 'role'            is distinct from to_jsonb(old) ->> 'role'
     or to_jsonb(new) ->> 'is_suspended' is distinct from to_jsonb(old) ->> 'is_suspended'
     or to_jsonb(new) ->> 'star_points'  is distinct from to_jsonb(old) ->> 'star_points' then
    raise exception 'CHAMP_PROTEGE : role, is_suspended et star_points ne sont pas modifiables directement'
      using errcode = '42501';
  end if;

  return new;
end;
$func$;

drop trigger if exists trg_profiles_verrou on public.profiles;
create trigger trg_profiles_verrou
  before update on public.profiles
  for each row execute function public.profiles_verrou_champs_sensibles();

commit;

-- ── Contrôles (à exécuter après le script) ──────────────────────────────────
-- En tant qu'utilisateur normal (pas admin), dans l'app ou avec son JWT :
--   update public.profiles set role = 'admin' where id = auth.uid();
--     attendu : ERREUR 42501 (CHAMP_PROTEGE) — l'escalade est bloquée.
--   update public.profiles set first_name = 'Test' where id = auth.uid();
--     attendu : SUCCESS — les champs de profil restent modifiables.
-- Vérifier les droits :
--   select privilege_type, column_name from information_schema.column_privileges
--    where table_name = 'profiles' and grantee = 'authenticated' and privilege_type = 'UPDATE'
--    order by column_name;
--     attendu : uniquement first_name, last_name, phone, email,
--               photo_profil_url, inscription_complete, country_code.
