-- ============================================================================
-- MonTotem — FINANCE : Script 13/13
-- Commission calculée côté serveur avec arrondi explicite par devise,
-- plafond de dette cash par prestataire et blocage des commandes cash.
--
--   1. commission_rules (extension additive) :
--        - montant_fixe   : commission forfaitaire (unités mineures de la
--                           devise de la course), remplace le % si renseignée ;
--        - min_commission / max_commission : plancher / plafond (unités
--                           mineures de la devise), appliqués au résultat.
--   2. calculer_commission(p_montant_minor, p_devise, p_service_category,
--      p_provider_kind, p_vehicle_type) : renvoie jsonb
--      { rule_id, devise, pct, montant_fixe, commission_minor, net_minor }.
--      Utilisée par les RPC de clôture et
--      par l'app pour l'estimation affichée (le calcul définitif reste
--      serveur).
--   3. est_bloque_cash(p_provider) : dette cash >= plafond effectif
--      (wallets.credit_limit sinon app_config.cash_credit_limit_fcfa).
--   4. payer_commission_cash(p_montant, p_client_request_id, p_operateur,
--      p_phone) : le prestataire rembourse sa dette cash
--      par Mobile Money ; écriture append-only 'debit_commission' avec
--      client_request_id (idempotence anti double-débit).
--   5. solde_wallet_prestataire() : photo jsonb du double ledger
--      (payable, dette, plafond, devise, bloque_cash) pour les écrans.
--   6. Trigger BEFORE INSERT/UPDATE sur rides : commande cash refusée si le
--      prestataire a dépassé son plafond. Aucun RPC existant (037/039)
--      n'est modifié : tout est additif.
--
-- Exécution : après 11 puis 12. Non destructif, idempotent.
-- Prérequis : commission_rules (019), app_config (003), wallets + ledger (12),
--             devises/zones + arrondir_devise (11).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Extension additive de commission_rules (règles hybrides % / fixe /
--    plancher / plafond). NULL = non renseigné = non appliqué.
-- ---------------------------------------------------------------------------
alter table public.commission_rules
  add column if not exists montant_fixe   numeric(14, 2),
  add column if not exists min_commission numeric(14, 2),
  add column if not exists max_commission numeric(14, 2);

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'ck_commission_rules_montants_positifs'
       and conrelid = 'public.commission_rules'::regclass
  ) then
    alter table public.commission_rules
      add constraint ck_commission_rules_montants_positifs
      check ((montant_fixe   is null or montant_fixe   >= 0)
         and (min_commission is null or min_commission >= 0)
         and (max_commission is null or max_commission >= 0));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Sélection de la règle la plus spécifique (3 essais : règle exacte,
--    puis sans vehicle_type, puis sans provider_kind), fallback 15 %.
-- ---------------------------------------------------------------------------
create or replace function public._commission_regle(
  p_service_category text,
  p_provider_kind    text,
  p_vehicle_type     text
) returns public.commission_rules
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_regle public.commission_rules;
begin
  select * into v_regle
    from public.commission_rules
   where actif
     and service_category = p_service_category
     and provider_kind is not distinct from p_provider_kind
     and vehicle_type is not distinct from p_vehicle_type
   limit 1;
  if v_regle.id is not null then
    return v_regle;
  end if;

  select * into v_regle
    from public.commission_rules
   where actif
     and service_category = p_service_category
     and provider_kind is not distinct from p_provider_kind
     and vehicle_type is null
   limit 1;
  if v_regle.id is not null then
    return v_regle;
  end if;

  select * into v_regle
    from public.commission_rules
   where actif
     and service_category = p_service_category
     and provider_kind is null
     and vehicle_type is null
   limit 1;
  return v_regle;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Calcul de commission DEFINITIF, côté serveur, arrondi par devise.
--    p_montant_minor : montant total payé par le client, en unités mineures.
-- ---------------------------------------------------------------------------
create or replace function public.calculer_commission(
  p_montant_minor    bigint,
  p_devise           text,
  p_service_category text default null,
  p_provider_kind    text default null,
  p_vehicle_type     text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_devise   text;
  v_regle    public.commission_rules;
  v_commission bigint;
  v_min   bigint;
  v_max   bigint;
begin
  if p_montant_minor is null or p_montant_minor < 0 then
    raise exception 'MONTANT_INVALIDE';
  end if;

  v_devise := upper(btrim(coalesce(p_devise, 'XOF')));
  if not exists (select 1 from public.devises where code = v_devise and actif) then
    raise exception 'DEVISE_INCONNUE : %', v_devise;
  end if;

  v_regle := public._commission_regle(
    coalesce(p_service_category, ''),
    nullif(btrim(coalesce(p_provider_kind, '')), ''),
    nullif(btrim(coalesce(p_vehicle_type, '')), ''));

  if v_regle.id is null then
    -- Aucune règle configurée pour cette catégorie : taux global par défaut.
    v_commission := null;
    v_commission := public.arrondir_devise(
      p_montant_minor
        * coalesce((select value_int from public.app_config
                     where key = 'commission_momo_pct'), 15) / 100.0,
      v_devise);
    return jsonb_build_object(
      'rule_id',         null,
      'devise',          v_devise,
      'pct',             coalesce((select value_int from public.app_config
                                   where key = 'commission_momo_pct'), 15),
      'montant_fixe',    null,
      'commission_minor', v_commission,
      'net_minor',       p_montant_minor - v_commission);
  end if;

  -- Commission fixe (si configurée) sinon pourcentage arrondi selon la devise.
  if v_regle.montant_fixe is not null then
    v_commission := public.arrondir_devise(v_regle.montant_fixe, v_devise);
  else
    v_commission := public.arrondir_devise(
      p_montant_minor * v_regle.pct / 100.0, v_devise);
  end if;

  -- Plancher / plafond exprimés en unités mineures de la devise de la course.
  v_min := nullif(v_regle.min_commission, 0)::bigint;
  v_max := nullif(v_regle.max_commission, 0)::bigint;
  if v_max is not null and v_commission > v_max then
    v_commission := v_max;
  end if;
  if v_min is not null and v_commission < v_min then
    v_commission := v_min;
  end if;
  if v_commission > p_montant_minor then
    v_commission := p_montant_minor;
  end if;

  return jsonb_build_object(
    'rule_id',          v_regle.id,
    'devise',           v_devise,
    'pct',              case when v_regle.montant_fixe is null
                             then v_regle.pct else null end,
    'montant_fixe',     v_regle.montant_fixe,
    'commission_minor', v_commission,
    'net_minor',        p_montant_minor - v_commission);
end;
$$;

revoke all on function public._commission_regle(text, text, text) from public;
revoke all on function public.calculer_commission(bigint, text, text, text, text) from public;
grant execute on function public.calculer_commission(bigint, text, text, text, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Plafond effectif de dette cash du prestataire.
-- ---------------------------------------------------------------------------
create or replace function public._credit_limit_effectif(p_provider uuid)
returns bigint
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(
    nullif((select credit_limit
              from public.wallets where provider_id = p_provider), 0),
    (select value_int::bigint from public.app_config
      where key = 'cash_credit_limit_fcfa'),
    5000::bigint)
$$;

create or replace function public.est_bloque_cash(p_provider uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(
           (select cash_commission_debt from public.wallets
             where provider_id = p_provider), 0)
         >= public._credit_limit_effectif(p_provider)
$$;

revoke all on function public.est_bloque_cash(uuid) from public;
grant execute on function public.est_bloque_cash(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Paiement de la dette cash par Mobile Money (dette ↓, ledger append-only,
--    idempotent via client_request_id). Ne touche pas au solde payable.
-- ---------------------------------------------------------------------------
create or replace function public.payer_commission_cash(
  p_montant           bigint,
  p_client_request_id text default null,
  p_operateur         text default null,
  p_phone             text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_provider uuid    := auth.uid();
  v_dette    bigint;
  v_devise   text;
  v_note     text;
  v_reponse  jsonb;
begin
  if v_provider is null then
    raise exception 'NON_CONNECTE';
  end if;
  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE';
  end if;

  -- Idempotence : une requête client déjà exécutée est rejouée sans effet.
  if p_client_request_id is not null and exists (
    select 1 from public.ledger_entries
     where client_request_id = p_client_request_id
       and kind = 'debit_commission'
       and provider_id = v_provider
  ) then
    select jsonb_build_object('deja_traite', true,
                              'dettes', cash_commission_debt)
      into v_reponse
      from public.wallets where provider_id = v_provider;
    return v_reponse;
  end if;

  v_devise := public.devise_du_prestataire(v_provider);

  update public.wallets
     set cash_commission_debt = cash_commission_debt - p_montant
   where provider_id = v_provider
     and cash_commission_debt >= p_montant
  returning cash_commission_debt into v_dette;

  if v_dette is null then
    raise exception 'MONTANT_SUPERIEUR_DETTE';
  end if;

  v_note := btrim(concat_ws(' | ',
    nullif(p_operateur, ''), nullif(p_phone, '')));

  insert into public.ledger_entries
    (provider_id, devise_code, kind, amount_minor, payable_after, debt_after,
     client_request_id, reference_id, note)
  values
    (v_provider, v_devise, 'debit_commission',
     -p_montant,
     (select payable_balance from public.wallets
       where provider_id = v_provider),
     v_dette,
     coalesce(p_client_request_id, format('cashpay:%s:%s', v_provider, now())),
     null, v_note);

  return jsonb_build_object('deja_traite', false, 'dettes', v_dette);
end;
$$;

revoke all on function public.payer_commission_cash(bigint, text, text, text) from public;
grant execute on function public.payer_commission_cash(bigint, text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Photo du double ledger pour les écrans prestataire. Ne lève jamais
--    pour un wallet absent (réponse zéros).
-- ---------------------------------------------------------------------------
create or replace function public.solde_wallet_prestataire()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_provider uuid := auth.uid();
  w public.wallets;
begin
  if v_provider is null then
    raise exception 'NON_CONNECTE';
  end if;

  select * into w from public.wallets where provider_id = v_provider;
  if w is null then
    return jsonb_build_object(
      'provider_id',          v_provider,
      'balance_fcfa',         0,
      'payable_balance',      0,
      'cash_commission_debt', 0,
      'credit_limit',         public._credit_limit_effectif(v_provider),
      'devise_code',          public.devise_du_prestataire(v_provider),
      'bloque_cash',          false);
  end if;

  return jsonb_build_object(
    'provider_id',          w.provider_id,
    'balance_fcfa',         w.balance_fcfa,
    'payable_balance',      w.payable_balance,
    'cash_commission_debt', w.cash_commission_debt,
    'credit_limit',         public._credit_limit_effectif(v_provider),
    'devise_code',          public.devise_du_prestataire(v_provider),
    'bloque_cash',          public.est_bloque_cash(v_provider));
end;
$$;

revoke all on function public.solde_wallet_prestataire() from public;
grant execute on function public.solde_wallet_prestataire() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Blocage anti-fraude : une commande CASH est refusée à l'insertion si le
--    prestataire a atteint son plafond de dette. Additif, sans toucher aux
--    triggers/RPC existants (037, 039, 18_apply_momo_commission).
-- ---------------------------------------------------------------------------
create or replace function public._verifier_plafond_cash()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.payment_method = 'cash'
     and new.provider_id is not null
     and public.est_bloque_cash(new.provider_id) then
    raise exception 'CASH_BLOQUE_PLAFOND_DEPASSE : %',
      format('dette %s >= plafond %s — rechargez votre compte par Mobile Money',
             (select cash_commission_debt from public.wallets
               where provider_id = new.provider_id),
             public._credit_limit_effectif(new.provider_id))
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_rides_plafond_cash on public.rides;
create trigger trg_rides_plafond_cash
  before insert or update of provider_id, payment_method on public.rides
  for each row execute function public._verifier_plafond_cash();

commit;