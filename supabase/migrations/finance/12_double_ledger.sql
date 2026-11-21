-- ============================================================================
-- MonTotem — FINANCE : Script 12/13
-- Double ledger prestataire + grand livre append-only.
--
--   wallets (extension additive, sans casser le solde existant) :
--     - payable_balance      : argent Mobile Money encaissé par la plateforme,
--                              retirable vers MoMo / banque ;
--     - cash_commission_debt : dette de commission accumulée sur les
--                              prestations payées en CASH (le pro garde
--                              100 % du cash, la dette augmente) ;
--     - credit_limit         : plafond de dette cash du prestataire
--                              (0 = utilise le plafond global app_config).
--
--   ledger_entries : grand livre append-only (client_request_id + reference_id
--     pour l'audit et l'idempotence). UPDATE et DELETE interdits.
--
--   Miroir automatique : tout mouvement existant de wallet_transactions
--     (triggers 039, topups 040, ajustements admin) alimente le double ledger
--     SANS modifier un seul RPC existant.
--
-- Exécution : après le script 11. Non destructif, idempotent.
-- Prérequis : wallets (015), wallet_transactions, providers, 11_devises_zones.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Colonnes du double ledger sur wallets
-- ---------------------------------------------------------------------------
alter table public.wallets
  add column if not exists payable_balance      bigint not null default 0;
alter table public.wallets
  add column if not exists cash_commission_debt bigint not null default 0;
alter table public.wallets
  add column if not exists credit_limit         bigint not null default 0;

-- Plafond de dette cash par défaut (surchargeable par prestataire par l'admin).
insert into public.app_config (key, value_int, note)
values ('cash_credit_limit_fcfa', 5000,
        'Plafond de dette cash par défaut (surcharge par wallets.credit_limit)')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Grand livre append-only
-- ---------------------------------------------------------------------------
create table if not exists public.ledger_entries (
  id                bigint generated always as identity primary key,
  provider_id       uuid        not null references public.providers (id) on delete cascade,
  devise_code       text        not null references public.devises (code),
  kind              text        not null check (kind in (
                      'cash_encaisse', 'commission_cash', 'commission_momo',
                      'commission_travel', 'momo_paiement', 'topup',
                      'debit_commission', 'ajustement', 'remboursement')),
  amount_minor      bigint      not null,
  payable_after     bigint,
  debt_after        bigint,
  client_request_id text,
  reference_id      text,
  note              text,
  created_at        timestamptz not null default now(),
  unique (client_request_id, kind)
);

create index if not exists ledger_entries_provider_idx
  on public.ledger_entries (provider_id, id desc);

-- Append-only strict : aucune modification ni suppression, jamais.
create or replace function public.ledger_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception 'LEDGER_IMMUTABLE : les écritures % du grand livre sont interdites (id %)',
    TG_OP, old.id;
end;
$$;

drop trigger if exists trg_ledger_no_update on public.ledger_entries;
create trigger trg_ledger_no_update
  before update on public.ledger_entries
  for each row execute function public.ledger_append_only();

drop trigger if exists trg_ledger_no_delete on public.ledger_entries;
create trigger trg_ledger_no_delete
  before delete on public.ledger_entries
  for each row execute function public.ledger_append_only();

alter table public.ledger_entries enable row level security;

drop policy if exists ledger_lecture_proprio on public.ledger_entries;
create policy ledger_lecture_proprio
  on public.ledger_entries for select
  to authenticated
  using (provider_id = auth.uid() or public.is_admin());

drop policy if exists ledger_ecriture_service on public.ledger_entries;
create policy ledger_ecriture_service
  on public.ledger_entries for insert
  to authenticated
  with check (provider_id = auth.uid() or public.is_admin());

grant select, insert on public.ledger_entries to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Mode de paiement d'origine d'une commission (cash vs MoMo)
-- ---------------------------------------------------------------------------
create or replace function public._commission_est_cash(
  p_kind      text,
  p_reference text
) returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_origin text;
begin
  -- commission_cash : par définition cash.
  if p_kind = 'commission_cash' then
    return true;
  end if;
  -- commission_momo : par définition MoMo.
  if p_kind = 'commission_momo' then
    return false;
  end if;
  -- commission_travel : l'origine est inscrie dans la référence.
  if p_reference like 'course:%' then
    select payment_method into v_origin
      from public.rides
     where id::text = split_part(p_reference, ':', 2);
    return coalesce(v_origin, 'momo') = 'cash';
  end if;
  if p_reference like 'trajet:%' then
    select operateur into v_origin
      from public.mission_payments
     where id::text = split_part(p_reference, ':', 2);
    return coalesce(v_origin, 'momo') = 'especes';
  end if;
  return false;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Miroir automatique : wallet_transactions alimente le double ledger.
--    Aucun trigger existant (039, 040) n'est modifié.
-- ---------------------------------------------------------------------------
create or replace function public._miroir_double_ledger()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_devise   text;
  v_cash     boolean;
  v_kind     text;
  v_amount   bigint;
  v_payable  bigint;
  v_debt     bigint;
begin
  -- 1. Caractéristiques du mouvement.
  v_amount := new.amount_fcfa::bigint;
  v_devise := public.devise_du_prestataire(new.provider_id);

  case new.kind
    when 'topup' then
      v_kind   := 'topup';
      v_cash   := false;
    when 'refund' then
      v_kind   := 'remboursement';
      v_cash   := false;
    when 'adjustment' then
      v_kind   := 'ajustement';
      v_cash   := false;
    when 'commission_cash' then
      v_kind   := 'commission_cash';
      v_cash   := true;
    when 'commission_momo' then
      v_kind   := 'commission_momo';
      v_cash   := false;
    when 'commission_travel' then
      v_cash   := public._commission_est_cash(new.kind, new.reference);
      v_kind   := 'commission_travel';
    else
      return new;
  end case;

  -- 2. Mise à jour du double ledger + écriture d'audit.
  update public.wallets
     set payable_balance =
           case when v_cash then payable_balance
                else payable_balance + v_amount end,
         cash_commission_debt =
           case when v_cash then cash_commission_debt - v_amount
                else cash_commission_debt end,
         updated_at = now()
   where provider_id = new.provider_id
  returning payable_balance, cash_commission_debt
       into v_payable, v_debt;

  -- 3. Écriture append-only avec référence source (idempotence client_request_id).
  insert into public.ledger_entries
    (provider_id, devise_code, kind, amount_minor, payable_after, debt_after,
     client_request_id, reference_id, note)
  values
    (new.provider_id, v_devise, v_kind, v_amount, v_payable, v_debt,
     coalesce(new.reference, format('wt:%s', new.id)),
     coalesce(new.ride_id::text, new.reference),
     new.note);

  return new;
end;
$$;

drop trigger if exists trg_wallet_miroir_ledger on public.wallet_transactions;
create trigger trg_wallet_miroir_ledger
  after insert on public.wallet_transactions
  for each row execute function public._miroir_double_ledger();

-- ---------------------------------------------------------------------------
-- 4b. Idempotence grand livre : une écriture miroir par mouvement source
-- ---------------------------------------------------------------------------
create or replace function public.ledger_trouve_doublon(p_client_request_id text)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.ledger_entries
     where client_request_id = p_client_request_id)
$$;

-- ---------------------------------------------------------------------------
-- 5. Rattrapage (backfill) : les wallets existants sont projetés dans le
--    double ledger sans perte. Exécuté une seule fois (idempotent).
-- ---------------------------------------------------------------------------
update public.wallets w
   set payable_balance      = greatest(w.balance_fcfa, 0)::bigint,
       cash_commission_debt = greatest(-w.balance_fcfa, 0)::bigint
 where not exists (
   select 1 from public.ledger_entries le
    where le.provider_id = w.provider_id);

commit;