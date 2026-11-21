begin;

set local search_path to public, extensions;

-- 1. Nettoyage préalable pour éviter les conflits de signature ou de paramètres
drop function if exists public.submit_wallet_topup(integer, text, text, text);
drop function if exists public.admin_credit_wallet(uuid, integer, text, text);
drop function if exists public.admin_review_wallet_topup(uuid, boolean, text);

-- 2. Soumission d'une recharge par un prestataire
create or replace function public.submit_wallet_topup(
  p_amount integer, p_operateur text, p_payer_phone text, p_transaction_ref text
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_pv    public.providers%rowtype;
  v_phone text := regexp_replace(coalesce(p_payer_phone, ''), '\s+', '', 'g');
  v_ref   text := btrim(coalesce(p_transaction_ref, ''));
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into v_pv from public.providers where id = v_uid;
  if not found then raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002'; end if;
  if p_amount is null or p_amount < 500 or p_amount > 1000000 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;
  if p_operateur is null or not exists (
    select 1 from public.payment_settings ps
     where ps.operateur = p_operateur and ps.actif) then
    raise exception 'OPERATEUR_INVALIDE' using errcode = '22023';
  end if;
  if v_phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'TELEPHONE_INVALIDE' using errcode = '22023';
  end if;
  if char_length(v_ref) < 6 or char_length(v_ref) > 60 then
    raise exception 'REFERENCE_INVALIDE' using errcode = '22023';
  end if;
  if exists (select 1 from public.wallet_topup_requests
             where provider_id = v_uid and statut = 'awaiting_validation') then
    raise exception 'DEMANDE_EN_COURS' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.wallet_topup_requests
              where lower(transaction_ref) = lower(v_ref) and statut <> 'rejected')
     or exists (select 1 from public.wallet_transactions
                where lower(reference) = lower(v_ref)) then
    raise exception 'REFERENCE_DEJA_UTILISEE' using errcode = 'P0001';
  end if;

  insert into public.wallet_topup_requests
    (provider_id, amount_fcfa, operateur, payer_phone, transaction_ref)
  values (v_uid, p_amount, p_operateur, v_phone, v_ref);

  perform public.safe_notify_admins(
    'topup_declared', 'Recharge de wallet à vérifier',
    v_pv.business_name || ' : ' || p_amount || ' FCFA (' || upper(p_operateur) || ')',
    jsonb_build_object('provider_id', v_uid));
end;
$$;
revoke all on function public.submit_wallet_topup(integer, text, text, text)
  from public, anon;
grant execute on function public.submit_wallet_topup(integer, text, text, text)
  to authenticated;

-- 3. Admin : crédit direct (utilisé par admin_review_wallet_topup)
create or replace function public.admin_credit_wallet(
  p_provider uuid, p_amount integer, p_reference text, p_note text default 'Recharge'
) returns integer
language plpgsql security definer set search_path = public, extensions
as $$
declare v_bal integer;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;
  if exists (select 1 from public.wallet_transactions
             where lower(reference) = lower(p_reference)) then
    raise exception 'REFERENCE_DEJA_UTILISEE' using errcode = 'P0001';
  end if;
  insert into public.wallets (provider_id, balance_fcfa)
  values (p_provider, p_amount)
  on conflict (provider_id) do update
     set balance_fcfa = public.wallets.balance_fcfa + p_amount, updated_at = now()
  returning balance_fcfa into v_bal;
  insert into public.wallet_transactions
    (provider_id, kind, amount_fcfa, balance_after, reference, note, created_by)
  values (p_provider, 'topup', p_amount, v_bal, p_reference, p_note, auth.uid());
  return v_bal;
end;
$$;
revoke all on function public.admin_credit_wallet(uuid, integer, text, text)
  from public, anon, authenticated;

-- 4. Admin : valider/refuser
create or replace function public.admin_review_wallet_topup(
  p_request_id uuid, p_approve boolean, p_reason text default null
) returns void
language plpgsql security definer set search_path = public, extensions
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
    v_bal := public.admin_credit_wallet(
      req.provider_id, req.amount_fcfa, req.transaction_ref,
      'Recharge ' || upper(req.operateur));
    update public.wallet_topup_requests
       set statut = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
     where id = req.id;
    perform public.safe_notify(req.provider_id, 'wallet_topup_approved',
      'Recharge créditée',
      req.amount_fcfa || ' FCFA ajoutés. Solde : ' || v_bal || ' FCFA.',
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
revoke all on function public.admin_review_wallet_topup(uuid, boolean, text)
  from public, anon;
grant execute on function public.admin_review_wallet_topup(uuid, boolean, text)
  to authenticated;

commit;