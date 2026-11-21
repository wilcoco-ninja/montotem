-- =============================================================================
-- MONTOTEM : Script 10 - Abonnements, identité, administration, push, urgences
-- Fichier  : sql/10_subscriptions_identity_admin.sql
-- Prérequis : scripts 01b, 04b, 05, 07, 08, 09 exécutés. Idempotent.
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Nettoyage préalable des fonctions sujettes à modification de signature
drop function if exists public.submit_subscription_request(text, text, text, text, text);
drop function if exists public.admin_review_subscription_request(uuid, text, text);
drop function if exists public.register_device_token(text, text);

-- -----------------------------------------------------------------------------
-- 1. Formules d'abonnement
-- -----------------------------------------------------------------------------
create table if not exists public.subscription_plans (
  palier       text primary key check (palier ~ '^[a-z0-9_]{2,30}$'),
  libelle      text not null,
  prix_fcfa    integer not null check (prix_fcfa > 0),
  duree_jours  integer not null default 30 check (duree_jours between 1 and 3650),
  actif        boolean not null default true,
  ordre        integer not null default 0,
  avantages    text[] not null default '{}',
  created_at   timestamptz not null default now()
);

alter table public.subscription_plans
  add column if not exists avantages text[] not null default '{}',
  add column if not exists ordre     integer not null default 0;

insert into public.subscription_plans (palier, libelle, prix_fcfa, duree_jours, actif, ordre, avantages)
values
  ('basic', 'Basic', 1500, 30, true, 1,
   array['Visible dans les recherches', 'Support standard']),
  ('essentiel', 'Essentiel', 4000, 90, true, 2,
   array['Visible dans les recherches', 'Support prioritaire', '-11% vs Basic']),
  ('premium', 'Premium', 15000, 365, true, 3,
   array['Priorité d''affichage sur la carte', 'Support prioritaire',
         'Badge "Prestataire fidèle"', '-17% vs Basic'])
on conflict (palier) do nothing;

-- -----------------------------------------------------------------------------
-- 2. Numéros de réception des abonnements (Mobile Money de la plateforme)
-- -----------------------------------------------------------------------------
create table if not exists public.payment_settings (
  operateur  text primary key check (operateur in ('mtn', 'moov', 'celtiis')),
  numero     text not null check (numero ~ '^\+[0-9]{8,15}$'),
  titulaire  text not null default 'MONTOTEM BENIN',
  actif      boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.payment_settings (operateur, numero, titulaire)
values ('mtn', '+2290167182343', 'MONTOTEM BENIN')
on conflict (operateur) do nothing;

-- -----------------------------------------------------------------------------
-- 3. Demandes d'abonnement
-- -----------------------------------------------------------------------------
create table if not exists public.subscription_requests (
  id               uuid primary key default gen_random_uuid(),
  provider_id      uuid not null references public.providers (id) on delete cascade,
  palier           text not null references public.subscription_plans (palier),
  montant_fcfa     integer not null check (montant_fcfa > 0),
  duree_jours      integer not null check (duree_jours > 0),
  operateur        text not null check (operateur in ('mtn', 'moov', 'celtiis')),
  payer_phone      text not null,
  transaction_ref  text not null,
  note             text,
  statut           text not null default 'awaiting_validation'
                   check (statut in ('awaiting_validation', 'approved', 'rejected')),
  rejection_reason text,
  reviewed_by      uuid references public.profiles (id) on delete set null,
  reviewed_at      timestamptz,
  ends_at          timestamptz,
  created_at       timestamptz not null default now()
);

create index if not exists idx_sub_requests_provider
  on public.subscription_requests (provider_id, created_at desc);
create index if not exists idx_sub_requests_statut
  on public.subscription_requests (statut, created_at desc);
create unique index if not exists uq_sub_requests_reference
  on public.subscription_requests (lower(transaction_ref));
create unique index if not exists uq_sub_requests_one_pending
  on public.subscription_requests (provider_id) where statut = 'awaiting_validation';

-- -----------------------------------------------------------------------------
-- 4. Jetons de notification push
-- -----------------------------------------------------------------------------
create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  platform   text not null check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now()
);
create index if not exists idx_device_tokens_user on public.device_tokens (user_id);

-- -----------------------------------------------------------------------------
-- 5. Numéros d'urgence
-- -----------------------------------------------------------------------------
create table if not exists public.emergency_numbers (
  country_code text primary key check (length(country_code) = 2),
  country_name text not null,
  police       text not null,
  fire         text not null,
  ambulance    text not null,
  general      text,
  confidence   text not null default 'a_confirmer'
               check (confidence in ('officiel', 'recoupe', 'a_confirmer')),
  source       text,
  verified_at  date,
  updated_at   timestamptz not null default now()
);

alter table public.emergency_numbers
  add column if not exists min_lat double precision,
  add column if not exists max_lat double precision,
  add column if not exists min_lng double precision,
  add column if not exists max_lng double precision;

-- -----------------------------------------------------------------------------
-- 6. RLS et privilèges
-- -----------------------------------------------------------------------------
alter table public.subscription_plans    enable row level security;
alter table public.payment_settings      enable row level security;
alter table public.subscription_requests enable row level security;
alter table public.device_tokens         enable row level security;
alter table public.emergency_numbers     enable row level security;

-- formules : lecture des formules actives, gestion par l'admin
drop policy if exists plans_select on public.subscription_plans;
create policy plans_select on public.subscription_plans
  for select to authenticated using (actif or public.is_admin());

drop policy if exists plans_insert on public.subscription_plans;
create policy plans_insert on public.subscription_plans
  for insert to authenticated with check (public.is_admin());

drop policy if exists plans_update on public.subscription_plans;
create policy plans_update on public.subscription_plans
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- numéros de réception : lecture des numéros actifs
drop policy if exists payment_settings_select on public.payment_settings;
create policy payment_settings_select on public.payment_settings
  for select to authenticated using (actif or public.is_admin());

-- demandes : propriétaire ou admin
drop policy if exists sub_requests_select on public.subscription_requests;
create policy sub_requests_select on public.subscription_requests
  for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

revoke all on public.subscription_plans, public.payment_settings,
             public.subscription_requests, public.device_tokens,
             public.emergency_numbers
  from anon;

revoke insert, update, delete on public.payment_settings,
             public.subscription_requests from authenticated;
revoke delete on public.subscription_plans from authenticated;
revoke all on public.device_tokens, public.emergency_numbers from authenticated;

grant insert, update on public.subscription_plans to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Gardes : wallet bloqué ET compte suspendu
-- -----------------------------------------------------------------------------
create or replace function public.guard_blocked_provider()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status = 'accepted'
     and old.status in ('requested', 'pending')
     and new.provider_id is not null then
    if exists (
      select 1 from public.wallets w
       where w.provider_id = new.provider_id and w.blocked
    ) then
      raise exception 'WALLET_BLOQUE' using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.profiles p
       where p.id = new.provider_id and p.is_suspended
    ) then
      raise exception 'COMPTE_SUSPENDU' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.providers_guard_available()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.disponible and not coalesce(old.disponible, false) then
    if new.statut_validation <> 'approved' then
      raise exception 'PRESTATAIRE_NON_VALIDE' using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.profiles p where p.id = new.id and p.is_suspended
    ) then
      raise exception 'COMPTE_SUSPENDU' using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.wallets w where w.provider_id = new.id and w.blocked
    ) then
      raise exception 'WALLET_BLOQUE' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. Vérification d'URL de fichier téléversé par l'utilisateur
-- -----------------------------------------------------------------------------
create or replace function public.is_own_upload_url(p_url text, p_uid uuid)
returns boolean
language sql
immutable
as $$
  select p_url is not null
     and p_url ~ '^https://'
     and position('/' || p_uid::text || '/' in p_url) > 0;
$$;

-- -----------------------------------------------------------------------------
-- 9. Abonnement : déclaration du paiement par le prestataire
-- -----------------------------------------------------------------------------
create or replace function public.submit_subscription_request(
  p_palier          text,
  p_operateur       text,
  p_payer_phone     text,
  p_transaction_ref text,
  p_note            text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_pv    public.providers%rowtype;
  v_plan  public.subscription_plans%rowtype;
  v_phone text := regexp_replace(coalesce(p_payer_phone, ''), '\s+', '', 'g');
  v_ref   text := btrim(coalesce(p_transaction_ref, ''));
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  select * into v_pv from public.providers where id = v_uid;
  if not found then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.subscription_requests sr
     where sr.provider_id = v_uid and sr.statut = 'awaiting_validation'
  ) then
    raise exception 'DEMANDE_EN_COURS' using errcode = 'P0001';
  end if;

  select * into v_plan from public.subscription_plans where palier = p_palier and actif;
  if not found then
    raise exception 'PALIER_INVALIDE' using errcode = '22023';
  end if;

  if p_operateur is null or not exists (
    select 1 from public.payment_settings ps where ps.operateur = p_operateur and ps.actif
  ) then
    raise exception 'OPERATEUR_INVALIDE' using errcode = '22023';
  end if;

  if v_phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'TELEPHONE_INVALIDE' using errcode = '22023';
  end if;
  if char_length(v_ref) < 6 or char_length(v_ref) > 60 then
    raise exception 'REFERENCE_INVALIDE' using errcode = '22023';
  end if;

  insert into public.subscription_requests
    (provider_id, palier, montant_fcfa, duree_jours, operateur, payer_phone, transaction_ref, note)
  values
    (v_uid, v_plan.palier, v_plan.prix_fcfa, v_plan.duree_jours, p_operateur, v_phone, v_ref, left(nullif(btrim(p_note), ''), 300));

  perform public.safe_notify_admins(
    'subscription_requested',
    'Nouvelle demande d''abonnement',
    'Le prestataire demande le palier ' || v_plan.libelle || ' (' || v_plan.prix_fcfa || ' FCFA).',
    jsonb_build_object('provider_id', v_uid, 'palier', v_plan.palier)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. Validation ou refus admin d'une demande d'abonnement
-- -----------------------------------------------------------------------------
create or replace function public.admin_review_subscription_request(
  p_request_id uuid,
  p_decision   text,
  p_reason     text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_req public.subscription_requests%rowtype;
  v_new_end timestamptz;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'DECISION_INVALIDE' using errcode = '22023';
  end if;

  select * into v_req from public.subscription_requests where id = p_request_id for update;
  if not found or v_req.statut <> 'awaiting_validation' then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  if p_decision = 'approved' then
    v_new_end := greatest(coalesce((select fin_abonnement from public.providers where id = v_req.provider_id), now()), now()) + (v_req.duree_jours || ' days')::interval;

    update public.subscription_requests
       set statut = 'approved',
           reviewed_by = v_uid,
           reviewed_at = now(),
           ends_at = v_new_end
     where id = v_req.id;

    update public.providers
       set fin_abonnement = v_new_end,
           updated_at = now()
     where id = v_req.provider_id;

    perform public.safe_notify(
      v_req.provider_id,
      'subscription_approved',
      'Abonnement validé !',
      'Votre abonnement a été validé avec succès jusqu''au ' || to_char(v_new_end, 'DD/MM/YYYY'),
      jsonb_build_object('ends_at', v_new_end)
    );
  else
    update public.subscription_requests
       set statut = 'rejected',
           reviewed_by = v_uid,
           reviewed_at = now(),
           rejection_reason = left(nullif(btrim(p_reason), ''), 300)
     where id = v_req.id;

    perform public.safe_notify(
      v_req.provider_id,
      'subscription_rejected',
      'Abonnement refusé',
      coalesce(nullif(btrim(p_reason), ''), 'Votre demande de paiement n''a pas pu être validée.'),
      jsonb_build_object('request_id', v_req.id)
    );
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 11. Enregistrement des jetons push (Device Tokens)
-- -----------------------------------------------------------------------------
create or replace function public.register_device_token(
  p_token    text,
  p_platform text
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if p_token is null or char_length(btrim(p_token)) < 10 then
    raise exception 'TOKEN_INVALIDE' using errcode = '22023';
  end if;
  if p_platform not in ('ios', 'android') then
    raise exception 'PLATEFORME_INVALIDE' using errcode = '22023';
  end if;

  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (btrim(p_token), v_uid, p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

-- -----------------------------------------------------------------------------
-- 12. Droits d'exécution RPC
-- -----------------------------------------------------------------------------
revoke all on function public.submit_subscription_request(text, text, text, text, text) from public, anon;
revoke all on function public.admin_review_subscription_request(uuid, text, text) from public, anon;
revoke all on function public.register_device_token(text, text) from public, anon;

grant execute on function public.submit_subscription_request(text, text, text, text, text) to authenticated;
grant execute on function public.admin_review_subscription_request(uuid, text, text) to authenticated;
grant execute on function public.register_device_token(text, text) to authenticated;

commit;