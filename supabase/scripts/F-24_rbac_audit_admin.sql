-- ============================================================================
-- MonTotem — F-24 : SÉCURISATION RBAC + JOURNAL D'AUDIT ADMIN
-- ============================================================================
-- 1. CORRECTIF CRITIQUE : la contrainte providers_provider_kind_check (013)
--    n'autorisait que 8 kinds alors que le trigger des métiers (F-19/F-23)
--    renvoie AUSSI 'remorquage' et 'lavage' pour
--    « Dépanneuse / Remorquage » et « Lavage auto & moto ».
--    Conséquence : l'inscription d'un pro dépanneuse ou lavage échouait avec
--    une violation de contrainte. La contrainte est réécrite avec les 10 kinds.
--
-- 2. JOURNAL D'AUDIT (Audit Logs) : chaque action sensible de l'admin est
--    journalisée automatiquement (déclencheurs) et sur demande (RPC) :
--      - modification des tarifs / paramètres (app_config),
--      - attribution / retrait de rôles admin (admin_roles),
--      - validation ou rejet d'un profil pro (providers.statut_validation).
--
-- Prérequis : 010 (is_admin/is_super_admin), 013, sql/07. Idempotent.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Contrainte provider_kind : les 10 kinds du trigger des métiers
-- ---------------------------------------------------------------------------
alter table public.providers
  drop constraint if exists providers_provider_kind_check;

alter table public.providers
  add constraint providers_provider_kind_check
  check (provider_kind in (
    'zemidjan',            -- moto 1 passager
    'tricycle_passenger',  -- cloboto 2-3 personnes
    'tricycle_fret',       -- kloboto colis
    'mecanicien',
    'vulcanisateur',
    'electricien',
    'garage',
    'station',
    'remorquage',          -- Dépanneuse / Remorquage (F-19)
    'lavage'               -- Lavage auto & moto (F-19)
  ));

-- ---------------------------------------------------------------------------
-- 2. Table du journal d'audit
-- ---------------------------------------------------------------------------
create table if not exists public.admin_audit_log (
  id         bigint generated always as identity primary key,
  -- NULL = action système (migration / éditeur SQL, hors session auth).
  admin_id   uuid default auth.uid()
             references public.profiles (id) on delete set null,
  action     text not null,
  cible      text,
  details    jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_admin_idx
  on public.admin_audit_log (admin_id, created_at desc);
create index if not exists admin_audit_log_action_idx
  on public.admin_audit_log (action, created_at desc);

alter table public.admin_audit_log enable row level security;

drop policy if exists admin_audit_log_select on public.admin_audit_log;
create policy admin_audit_log_select on public.admin_audit_log
  for select to authenticated
  using (public.is_admin());

-- Aucune écriture directe : tout passe par les déclencheurs ou le RPC.
revoke insert, update, delete on public.admin_audit_log
  from authenticated, anon;
grant select on public.admin_audit_log to authenticated;

-- ---------------------------------------------------------------------------
-- 3. RPC d'audit manuel (admin uniquement) — pour les écrans Dart
-- ---------------------------------------------------------------------------
create or replace function public.journaliser_action_admin(
  p_action  text,
  p_cible   text default null,
  p_details jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $func$
begin
  if not public.is_admin() then
    raise exception 'RESERVE_ADMIN' using errcode = '42501';
  end if;
  insert into public.admin_audit_log (admin_id, action, cible, details)
  values (auth.uid(), p_action, p_cible, p_details);
end;
$func$;
revoke all on function public.journaliser_action_admin(text, text, jsonb)
  from public, anon;
grant execute on function public.journaliser_action_admin(text, text, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Déclencheurs automatiques d'audit
-- ---------------------------------------------------------------------------
-- a) Tarifs / paramètres métier (app_config)
create or replace function public.audit_app_config_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $func$
begin
  insert into public.admin_audit_log (admin_id, action, cible, details)
  values (
    auth.uid(),
    case tg_op when 'INSERT' then 'CONFIG_CREEE'
               when 'UPDATE' then 'CONFIG_MODIFIEE'
               else 'CONFIG_SUPPRIMEE' end,
    coalesce(new.key, old.key),
    jsonb_build_object(
      'ancien', case when tg_op = 'DELETE' then null else to_jsonb(old) end,
      'nouveau', case when tg_op = 'DELETE' then null else to_jsonb(new) end
    )
  );
  return coalesce(new, old);
end;
$func$;

drop trigger if exists trg_audit_app_config on public.app_config;
create trigger trg_audit_app_config
  after insert or update or delete on public.app_config
  for each row execute function public.audit_app_config_change();

-- b) Rôles admin (attribution / retrait)
create or replace function public.audit_admin_roles_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $func$
begin
  insert into public.admin_audit_log (admin_id, action, cible, details)
  values (
    auth.uid(),
    case tg_op when 'INSERT' then 'ROLE_ADMIN_ATTRIBUE'
               when 'UPDATE' then 'ROLE_ADMIN_MODIFIE'
               else 'ROLE_ADMIN_RETIRE' end,
    coalesce(new.user_id::text, old.user_id::text),
    jsonb_build_object(
      'ancien', case when tg_op = 'DELETE' then null else to_jsonb(old) end,
      'nouveau', case when tg_op = 'DELETE' then null else to_jsonb(new) end
    )
  );
  return coalesce(new, old);
end;
$func$;

drop trigger if exists trg_audit_admin_roles on public.admin_roles;
create trigger trg_audit_admin_roles
  after insert or update or delete on public.admin_roles
  for each row execute function public.audit_admin_roles_change();

-- c) Validation des profils pro (identité, photos)
create or replace function public.audit_providers_validation()
returns trigger
language plpgsql
security definer
set search_path = public
as $func$
begin
  if (tg_op = 'UPDATE'
      and (new.statut_validation is distinct from old.statut_validation
           or new.validated_by is distinct from old.validated_by)) then
    insert into public.admin_audit_log (admin_id, action, cible, details)
    values (
      auth.uid(),
      case new.statut_validation
        when 'approved' then 'PRO_VALIDE'
        when 'rejected' then 'PRO_REJETE'
        else 'PRO_REMIS_EN_ATTENTE' end,
      new.id::text,
      jsonb_build_object(
        'ancien_statut', old.statut_validation,
        'nouveau_statut', new.statut_validation,
        'raison', new.rejection_reason
      )
    );
  end if;
  return coalesce(new, old);
end;
$func$;

drop trigger if exists trg_audit_providers_validation on public.providers;
create trigger trg_audit_providers_validation
  after update on public.providers
  for each row execute function public.audit_providers_validation();

commit;

-- ── Contrôles (à exécuter après le script) ──
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--  where conname = 'providers_provider_kind_check';
--   attendu : 10 kinds dont remorquage et lavage.
-- insert into public.app_config(key, value_int) values ('_test_audit', 1)
--  on conflict (key) do update set value_int = 1 returning key;
-- select action, cible, created_at from public.admin_audit_log order by id desc limit 3;
-- delete from public.app_config where key = '_test_audit';
