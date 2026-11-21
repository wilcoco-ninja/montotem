-- =============================================================================
-- MONTOTEM : Script 21 - Seuil de blocage robuste + objets de recharge wallet
-- Idempotent. Ne remplace jamais une fonction de recharge déjà en place.
-- =============================================================================

create temp table if not exists tmp_rapport (rubrique text, detail text);
truncate tmp_rapport;

-- 0. Etat avant correction -----------------------------------------------------
insert into tmp_rapport
select 'AVANT : seuil app_config', coalesce(c.value_int::text, 'absent')
  from (select 1) x
  left join public.app_config c on c.key = 'wallet_block_threshold_fcfa';

insert into tmp_rapport
select 'AVANT : prestataires bloques', count(*)::text
  from public.wallets
 where blocked;

-- Sauvegarde (une seule fois) de la fonction avant remplacement
create table if not exists public._backup_functions_21 as
select p.proname::text as proname,
       pg_get_functiondef(p.oid) as def,
       now() as saved_at
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname = 'check_wallet_block';

alter table public._backup_functions_21 enable row level security;

-- 1. Seuil toujours positif en base (règle : bloqué quand solde < -seuil) ------
insert into public.app_config (key, value_int, note)
select 'wallet_block_threshold_fcfa', 2000,
       'Prestataire bloque quand solde wallet < -seuil (FCFA)'
 where not exists (
   select 1 from public.app_config c where c.key = 'wallet_block_threshold_fcfa'
 );

update public.app_config
   set value_int = abs(value_int)
 where key = 'wallet_block_threshold_fcfa'
   and value_int < 0;

-- 2. check_wallet_block tolérante au signe ------------------------------------
create or replace function public.check_wallet_block(p_provider uuid)
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_threshold integer;
  v_bal       integer;
  v_blocked   boolean;
  v_reason    text;
begin
  select abs(coalesce(
           (select c.value_int from public.app_config c
             where c.key = 'wallet_block_threshold_fcfa'), 2000))
    into v_threshold;

  select w.balance_fcfa, w.blocked, w.block_reason
    into v_bal, v_blocked, v_reason
    from public.wallets w
   where w.provider_id = p_provider
   for update;
  if not found then
    return false;
  end if;

  if v_bal < -v_threshold then
    if not v_blocked then
      update public.wallets
         set blocked = true, blocked_at = now(),
             block_reason = 'solde_negatif', updated_at = now()
       where provider_id = p_provider;
    end if;
    return true;
  elsif v_blocked and v_reason = 'solde_negatif' then
    update public.wallets
       set blocked = false, blocked_at = null,
           block_reason = null, updated_at = now()
     where provider_id = p_provider;
    return false;
  end if;

  return v_blocked;
end;
$$;

revoke all on function public.check_wallet_block(uuid) from public, anon, authenticated;

-- 3. Réévaluation des comptes bloqués (débloque ceux bloqués à tort) -----------
do $$
declare
  r record;
begin
  for r in select w.provider_id from public.wallets w where w.blocked loop
    perform public.check_wallet_block(r.provider_id);
  end loop;
end
$$;

-- 4. Objets de recharge : créés seulement s'ils n'existent pas ----------------
do $outer$
begin
  if to_regclass('public.wallet_topup_requests') is null then
    create table public.wallet_topup_requests (
      id               uuid primary key default gen_random_uuid(),
      provider_id      uuid not null references public.providers (id) on delete cascade,
      amount_fcfa      integer not null check (amount_fcfa > 0),
      operateur        text not null,
      payer_phone      text not null,
      transaction_ref  text not null,
      statut           text not null default 'awaiting_validation'
        check (statut in ('awaiting_validation', 'approved', 'rejected')),
      rejection_reason text,
      reviewed_by      uuid references public.profiles (id),
      reviewed_at      timestamptz,
      created_at       timestamptz not null default now()
    );

    create unique index uq_wallet_topup_ref
      on public.wallet_topup_requests (lower(transaction_ref));
    create index idx_wallet_topup_provider
      on public.wallet_topup_requests (provider_id, created_at desc);
    create index idx_wallet_topup_statut
      on public.wallet_topup_requests (statut, created_at desc);

    alter table public.wallet_topup_requests enable row level security;

    create policy wallet_topup_select
      on public.wallet_topup_requests
      for select to authenticated
      using (provider_id = (select auth.uid()) or public.is_admin());

    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (
         select 1 from pg_publication_tables
          where pubname = 'supabase_realtime'
            and schemaname = 'public'
            and tablename = 'wallet_topup_requests') then
      alter publication supabase_realtime add table public.wallet_topup_requests;
    end if;

    insert into tmp_rapport values ('Recharges', 'table creee');
  end if;

  if to_regprocedure('public.submit_wallet_topup(integer,text,text,text)') is null then
    execute $fn$
      create or replace function public.submit_wallet_topup(
        p_amount integer,
        p_operateur text,
        p_payer_phone text,
        p_transaction_ref text
      ) returns uuid
      language plpgsql
      security definer
      set search_path = ''
      as $body$
      declare
        v_uid   uuid := auth.uid();
        v_ref   text := btrim(coalesce(p_transaction_ref, ''));
        v_phone text := btrim(coalesce(p_payer_phone, ''));
        v_id    uuid;
        v_nom   text;
      begin
        if v_uid is null then
          raise exception 'NON_CONNECTE' using errcode = '28000';
        end if;
        if not exists (select 1 from public.providers pv where pv.id = v_uid) then
          raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
        end if;
        if p_amount is null or p_amount < 1000 or p_amount > 1000000 then
          raise exception 'MONTANT_INVALIDE' using errcode = '22023';
        end if;
        if lower(coalesce(p_operateur, '')) not in ('mtn', 'moov', 'celtiis') then
          raise exception 'OPERATEUR_INVALIDE' using errcode = '22023';
        end if;
        if v_phone !~ '^\+?[0-9]{8,15}$' then
          raise exception 'TELEPHONE_INVALIDE' using errcode = '22023';
        end if;
        if length(v_ref) < 6 then
          raise exception 'REFERENCE_INVALIDE' using errcode = '22023';
        end if;
        if exists (
          select 1 from public.wallet_topup_requests t
           where t.provider_id = v_uid and t.statut = 'awaiting_validation'
        ) then
          raise exception 'DEMANDE_EN_COURS' using errcode = '23000';
        end if;
        if exists (
          select 1 from public.wallet_topup_requests t
           where lower(t.transaction_ref) = lower(v_ref)
        ) then
          raise exception 'REFERENCE_DEJA_UTILISEE' using errcode = '23505';
        end if;

        insert into public.wallet_topup_requests
          (provider_id, amount_fcfa, operateur, payer_phone, transaction_ref)
        values (v_uid, p_amount, lower(p_operateur), v_phone, v_ref)
        returning id into v_id;

        select coalesce(nullif(btrim(pv.business_name), ''), 'Un prestataire')
          into v_nom
          from public.providers pv
         where pv.id = v_uid;

        perform public.notify_admins(
          'wallet_topup_submitted',
          'Recharge à vérifier',
          v_nom || ' déclare une recharge de ' || p_amount || ' FCFA (réf. ' || v_ref || ').',
          jsonb_build_object('request_id', v_id, 'provider_id', v_uid)
        );

        return v_id;
      end;
      $body$;
    $fn$;

    execute 'revoke all on function public.submit_wallet_topup(integer,text,text,text) from public, anon';
    execute 'grant execute on function public.submit_wallet_topup(integer,text,text,text) to authenticated';
    insert into tmp_rapport values ('Recharges', 'fonction submit_wallet_topup creee');
  end if;

  if to_regprocedure('public.admin_review_wallet_topup(uuid,boolean,text)') is null then
    execute $fn$
      create or replace function public.admin_review_wallet_topup(
        p_request_id uuid,
        p_approve boolean,
        p_reason text default null
      ) returns void
      language plpgsql
      security definer
      set search_path = ''
      as $body$
      declare
        v_uid    uuid := auth.uid();
        v_r      public.wallet_topup_requests%rowtype;
        v_bal    integer;
        v_motif  text := nullif(btrim(coalesce(p_reason, '')), '');
      begin
        if not public.is_admin() then
          raise exception 'INTERDIT' using errcode = '42501';
        end if;

        select * into v_r
          from public.wallet_topup_requests
         where id = p_request_id
         for update;
        if not found then
          raise exception 'INTROUVABLE' using errcode = 'P0002';
        end if;
        if v_r.statut <> 'awaiting_validation' then
          raise exception 'DEJA_TRAITEE' using errcode = '23000';
        end if;
        if v_r.amount_fcfa <= 0 then
          raise exception 'MONTANT_INVALIDE' using errcode = '22023';
        end if;

        if p_approve then
          insert into public.wallets (provider_id, balance_fcfa)
          values (v_r.provider_id, v_r.amount_fcfa)
          on conflict (provider_id) do update
             set balance_fcfa = public.wallets.balance_fcfa + v_r.amount_fcfa,
                 updated_at   = now()
          returning balance_fcfa into v_bal;

          insert into public.wallet_transactions
            (provider_id, kind, amount_fcfa, balance_after, reference, note)
          values
            (v_r.provider_id, 'topup', v_r.amount_fcfa, v_bal,
             'topup:' || v_r.id::text,
             'Recharge ' || upper(v_r.operateur) || ' · réf. ' || v_r.transaction_ref);

          update public.wallet_topup_requests
             set statut = 'approved', reviewed_by = v_uid, reviewed_at = now()
           where id = v_r.id;

          perform public.check_wallet_block(v_r.provider_id);

          perform public.notify_user(
            v_r.provider_id, 'wallet_topup_approved', 'Recharge validée',
            'Votre portefeuille a été crédité de ' || v_r.amount_fcfa || ' FCFA.',
            jsonb_build_object('request_id', v_r.id));
        else
          if v_motif is null then
            raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
          end if;

          update public.wallet_topup_requests
             set statut = 'rejected', rejection_reason = v_motif,
                 reviewed_by = v_uid, reviewed_at = now()
           where id = v_r.id;

          perform public.notify_user(
            v_r.provider_id, 'wallet_topup_rejected', 'Recharge refusée',
            'Motif : ' || v_motif,
            jsonb_build_object('request_id', v_r.id));
        end if;
      end;
      $body$;
    $fn$;

    execute 'revoke all on function public.admin_review_wallet_topup(uuid,boolean,text) from public, anon';
    execute 'grant execute on function public.admin_review_wallet_topup(uuid,boolean,text) to authenticated';
    insert into tmp_rapport values ('Recharges', 'fonction admin_review_wallet_topup creee');
  end if;
end
$outer$;

-- 5. Rapport ----------------------------------------------------------------------
insert into tmp_rapport
select 'APRES : seuil app_config', coalesce(c.value_int::text, 'absent')
  from (select 1) x
  left join public.app_config c on c.key = 'wallet_block_threshold_fcfa';

insert into tmp_rapport
select 'APRES : prestataires bloques', count(*)::text
  from public.wallets
 where blocked;

insert into tmp_rapport
select 'Fonction lisant le seuil', p.proname::text
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.prosrc ilike '%wallet_block_threshold_fcfa%';

insert into tmp_rapport
select 'Trigger sur wallets', t.tgname::text
  from pg_trigger t
 where t.tgrelid = 'public.wallets'::regclass
   and not t.tgisinternal;

insert into tmp_rapport
select 'Recharges : objet present', n.nom
  from (values
    ('table wallet_topup_requests', to_regclass('public.wallet_topup_requests') is not null),
    ('fonction submit_wallet_topup',
       to_regprocedure('public.submit_wallet_topup(integer,text,text,text)') is not null),
    ('fonction admin_review_wallet_topup',
       to_regprocedure('public.admin_review_wallet_topup(uuid,boolean,text)') is not null)
  ) as n(nom, ok)
 where n.ok;

select rubrique, detail from tmp_rapport order by rubrique, detail;