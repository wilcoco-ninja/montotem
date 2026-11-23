-- ============================================================================
-- MonTotem - FINANCE : Script 14 / script 14 admin pilotage
-- Pilotage administrateur cote serveur :
--   1. admin_set_config      : ecriture securisee des cles entieres
--                              app_config (plafond dette cash, seuil blocage);
--   2. admin_ajuster_ledger  : ajustement / remboursement manuel du grand
--                              livre, soldes payable_after / debt_after
--                              recalcules cote serveur, idempotence via
--                              client_request_id (anti double-clic).
--
-- Non destructif, idempotent. Aucune table ni colonne modifiee.
-- Prerequis : 010 (is_admin), 003 (app_config), finance/11 (devises),
--             finance/12 (ledger_entries, colonnes wallets).
-- Le montant reste en unites MINEURES entieres (bigint), jamais en double.
-- ============================================================================

begin;

set local search_path to public, extensions;

-- ---------------------------------------------------------------------------
-- 1. admin_set_config - ecriture d'une cle entiere app_config, garde admin
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_config(
  p_key       text,
  p_value_int bigint default null,
  p_note      text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  v_key := coalesce(btrim(p_key), '');
  if v_key = '' or length(v_key) > 80 then
    raise exception 'CLE_INVALIDE' using errcode = '22023';
  end if;

  if p_value_int is null or p_value_int < 0
     or p_value_int > 1000000000::bigint then
    raise exception 'VALEUR_INVALIDE' using errcode = '22023';
  end if;

  -- Borne de securite : seules les cles de plafond/blocage sont admises ici.
  if v_key not in ('cash_credit_limit_fcfa', 'wallet_block_threshold_fcfa') then
    raise exception 'CLE_INVALIDE' using errcode = '22023';
  end if;

  insert into public.app_config (key, value_int, note, updated_at)
  values (v_key, p_value_int::integer, p_note, now())
  on conflict (key) do update
    set value_int  = excluded.value_int,
        note       = coalesce(excluded.note, public.app_config.note),
        updated_at = now();
end;
$$;

grant execute on function public.admin_set_config(text, bigint, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. admin_ajuster_ledger - litige : credit (> 0) ou debit (< 0) de la poche
--    Mobile Money d'un prestataire, genre 'ajustement' ou 'remboursement'.
--    Meme semantique que le miroir finance/12 : la dette cash n'est PAS
--    touchee ici (elle decrot uniquement via payer_commission_cash).
-- ---------------------------------------------------------------------------
create or replace function public.admin_ajuster_ledger(
  p_provider          uuid,
  p_devise            text,
  p_montant_minor     bigint,
  p_kind              text,
  p_note              text default null,
  p_client_request_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind      text;
  v_devise    text;
  v_wallet    record;
  v_payable   bigint;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  v_kind := coalesce(btrim(p_kind), '');
  if v_kind not in ('ajustement', 'remboursement') then
    raise exception 'GENRE_INVALIDE' using errcode = '22023';
  end if;

  if p_montant_minor is null or p_montant_minor = 0
     or abs(p_montant_minor) > 1000000000::bigint then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  v_devise := upper(coalesce(btrim(p_devise), ''));
  if not exists (
    select 1 from public.devises where code = v_devise
  ) then
    raise exception 'DEVISE_INVALIDE' using errcode = '22023';
  end if;

  select payable_balance, cash_commission_debt
    into v_wallet
    from public.wallets
   where provider_id = p_provider;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  -- Idempotence : meme client_request_id + meme genre => deja enregistre.
  if p_client_request_id is not null and exists (
    select 1 from public.ledger_entries
     where client_request_id = p_client_request_id
       and kind = v_kind
  ) then
    raise exception 'DOUBLON' using errcode = '23505';
  end if;

  -- Mise a jour de la poche payable (jamais negative), dette inchangee.
  v_payable := greatest(coalesce(v_wallet.payable_balance, 0) + p_montant_minor, 0);

  update public.wallets
     set payable_balance = v_payable,
         updated_at      = now()
   where provider_id = p_provider;

  insert into public.ledger_entries
    (provider_id, devise_code, kind, amount_minor, payable_after, debt_after,
     client_request_id, reference_id, note)
  values
    (p_provider, v_devise, v_kind, p_montant_minor, v_payable,
     coalesce(v_wallet.cash_commission_debt, 0),
     nullif(btrim(coalesce(p_client_request_id, '')), ''),
     null,
     left(nullif(btrim(coalesce(p_note, '')), ''), 300));
end;
$$;

grant execute on function public.admin_ajuster_ledger(
  uuid, text, bigint, text, text, text) to authenticated;

commit;

-- ============================================================================
-- FIN script 14.
-- ============================================================================