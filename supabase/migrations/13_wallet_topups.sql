-- =============================================================================
-- MONTOTEM : Script 13 - Recharges de wallet (déclaration + validation admin)
-- Fichier  : sql/13_wallet_topups.sql
-- Prérequis : scripts 01b à 12 exécutés. Idempotent.
-- =============================================================================
begin;

set local search_path to public, extensions;

-- -----------------------------------------------------------------------------
-- 1. Table des demandes de recharge
-- -----------------------------------------------------------------------------
create table if not exists public.wallet_topup_requests (
  id               uuid primary key default gen_random_uuid(),
  provider_id      uuid not null references public.providers (id) on delete cascade,
  amount_fcfa      integer not null check (amount_fcfa between 500 and 1000000),
  operateur        text not null check (operateur in ('mtn', 'moov', 'celtiis')),
  payer_phone      text not null,
  transaction_ref  text not null,
  statut           text not null default 'awaiting_validation'
                   check (statut in ('awaiting_validation', 'approved', 'rejected')),
  rejection_reason text,
  reviewed_by      uuid references public.profiles (id) on delete set null,
  reviewed_at      timestamptz,
  created_at       timestamptz not null default now()
);

create index if not exists idx_topups_provider
  on public.wallet_topup_requests (provider_id, created_at desc);
create index if not exists idx_topups_statut
  on public.wallet_topup_requests (statut, created_at desc);

-- Une référence refusée peut être redéclarée (erreur de saisie).
create unique index if not exists uq_topups_reference_active
  on public.wallet_topup_requests (lower(transaction_ref))
  where statut <> 'rejected';

create unique index if not exists uq_topups_one_pending
  on public.wallet_topup_requests (provider_id)
  where statut = 'awaiting_validation';

-- -----------------------------------------------------------------------------
-- 2. RLS : lecture propriétaire ou admin, écriture par RPC uniquement
-- -----------------------------------------------------------------------------
alter table public.wallet_topup_requests enable row level security;

drop policy if exists topups_select on public.wallet_topup_requests;
create policy topups_select on public.wallet_topup_requests
  for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

revoke all on public.wallet_topup_requests from anon;
revoke insert, update, delete on public.wallet_topup_requests from authenticated;

-- -----------------------------------------------------------------------------
-- 3. Déclaration par le prestataire
-- -----------------------------------------------------------------------------
create or replace function public.submit_wallet_topup(
  p_amount          integer,
  p_operateur       text,
  p_payer_phone     text,
  p_transaction_ref text
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_pv    public.providers%rowtype;
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

  if p_amount is null or p_amount < 500 or p_amount > 1000000 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  if p_operateur is null or not exists (
    select 1 from public.payment_settings ps
     where ps.operateur = p_operateur and ps.actif
  ) then
    raise exception 'OPERATEUR_INVALIDE' using errcode = '22023';
  end if;

  if v_phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'TELEPHONE_INVALIDE' using errcode = '22023';
  end if;
  if char_length(v_ref) < 6 or char_length(v_ref) > 60 then
    raise exception 'REFERENCE_INVALIDE' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.wallet_topup_requests t
     where t.provider_id = v_uid and t.statut = 'awaiting_validation'
  ) then
    raise exception 'DEMANDE_EN_COURS' using errcode = 'P0001';
  end if;

  -- Une même référence ne peut payer qu'une seule chose.
  if exists (
       select 1 from public.wallet_topup_requests t
        where lower(t.transaction_ref) = lower(v_ref) and t.statut <> 'rejected'
     )
     or exists (
       select 1 from public.subscription_requests s
        where lower(s.transaction_ref) = lower(v_ref) and s.statut <> 'rejected'
     )
     or exists (
       select 1 from public.wallet_transactions w
        where lower(w.reference) = lower(v_ref)
     ) then
    raise exception 'REFERENCE_DEJA_UTILISEE' using errcode = 'P0001';
  end if;

  insert into public.wallet_topup_requests
    (provider_id, amount_fcfa, operateur, payer_phone, transaction_ref)
  values
    (v_uid, p_amount, p_operateur, v_phone, v_ref);

  perform public.safe_notify_admins(
    'topup_declared', 'Recharge de wallet à vérifier',
    v_pv.business_name || ' : ' || p_amount || ' FCFA (' || upper(p_operateur) || ')',
    jsonb_build_object('provider_id', v_uid));
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Validation / refus par l'admin
-- -----------------------------------------------------------------------------
create or replace function public.admin_review_wallet_topup(
  p_request_id uuid,
  p_approve    boolean,
  p_reason     text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_reason text := nullif(btrim(p_reason), '');
  req      public.wallet_topup_requests%rowtype;
  v_bal    integer;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  select * into req from public.wallet_topup_requests
   where id = p_request_id for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  if req.statut <> 'awaiting_validation' then
    raise exception 'DEJA_TRAITEE' using errcode = 'P0001';
  end if;

  if p_approve then
    -- Le crédit utilise la référence MoMo comme clé unique : impossible de
    -- créditer deux fois la même transaction.
    v_bal := public.admin_credit_wallet(
      req.provider_id, req.amount_fcfa, req.transaction_ref,
      'Recharge ' || upper(req.operateur));

    update public.wallet_topup_requests
       set statut = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
     where id = req.id;

    perform public.safe_notify(req.provider_id, 'wallet_topup_approved',
      'Recharge créditée',
      req.amount_fcfa || ' FCFA ajoutés à votre wallet. Solde : ' || v_bal || ' FCFA.',
      jsonb_build_object('request_id', req.id));
  else
    if v_reason is null then
      raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
    end if;

    update public.wallet_topup_requests
       set statut = 'rejected', rejection_reason = left(v_reason, 300),
           reviewed_by = auth.uid(), reviewed_at = now()
     where id = req.id;

    perform public.safe_notify(req.provider_id, 'wallet_topup_rejected',
      'Recharge non validée', left(v_reason, 140),
      jsonb_build_object('request_id', req.id));
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. Droits d'exécution et Realtime
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('submit_wallet_topup', 'admin_review_wallet_topup')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

do $$
begin
  begin
    alter publication supabase_realtime add table public.wallet_topup_requests;
  exception when duplicate_object then null;
  end;
end $$;

commit;