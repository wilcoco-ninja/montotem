begin;

set local search_path to public, extensions;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. safe_notify / safe_notify_admins — wrappers jamais bloquants
--    (utilisés par 09, 10, 13, 14 mais jamais créés)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.safe_notify(
  p_user  uuid, p_type text, p_title text,
  p_body  text default null, p_data jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_user is null then return; end if;
  begin
    perform public.notify_user(p_user, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
  exception when others then null; end;
end;
$$;

create or replace function public.safe_notify_admins(
  p_type text, p_title text,
  p_body text default null, p_data jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  begin
    perform public.notify_admins(p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
  exception when others then null; end;
end;
$$;

revoke all on function public.safe_notify(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.safe_notify_admins(text, text, text, jsonb) from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. admin_dashboard_stats — Dashboard
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_out jsonb;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'total_users',        (select count(*) from public.profiles where role <> 'admin'),
    'total_providers',    (select count(*) from public.providers where statut_validation = 'approved'),
    'pending_providers',  (select count(*) from public.providers where statut_validation = 'pending'),
    'pending_payments',   (select count(*) from public.subscription_requests where statut = 'awaiting_validation')
                          + (select count(*) from public.wallet_topup_requests where statut = 'awaiting_validation'),
    'active_requests',    (select count(*) from public.missions
                            where status in ('pending','accepted','arrived','working'))
                          + (select count(*) from public.rides
                            where status in ('requested','accepted','arrived','in_progress')),
    'completed_requests', (select count(*) from public.missions where status = 'completed'),
    'open_reports',       (select count(*) from public.provider_reports
                            where status in ('open','reviewing')),
    'revenue_30d_fcfa',   coalesce((
        select sum(amount_fcfa)
          from public.wallet_transactions
         where kind in ('commission_cash','commission_momo','commission_travel')
           and created_at > now() - interval '30 days'), 0)
  ) into v_out;

  return v_out;
end;
$$;
grant execute on function public.admin_dashboard_stats() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. admin_finance_summary — onglet Finances de la Tour de Contrôle
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.admin_finance_summary(p_days integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_days  integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from  timestamptz := now() - make_interval(days => v_days);
  v_out   jsonb;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'series', coalesce((
      select jsonb_agg(jsonb_build_object('day', to_char(d, 'DD/MM'), 'income', coalesce(s, 0)) order by d)
        from (
          select date_trunc('day', g)::date as d,
                 (select coalesce(sum(amount_fcfa), 0)
                    from public.wallet_transactions t
                   where t.kind in ('commission_cash','commission_momo','commission_travel')
                     and t.created_at::date = g::date) as s
            from generate_series(v_from::date, now()::date, interval '1 day') g
        ) x
    ), '[]'::jsonb),
    'subscriptions_fcfa',              coalesce((select sum(montant_fcfa)
        from public.subscription_requests
       where statut = 'approved' and reviewed_at > v_from), 0),
    'missions_paid_fcfa',              coalesce((select sum(paid_fcfa)
        from public.missions where created_at > v_from), 0),
    'missions_billed_fcfa',            coalesce((select sum(travel_fee_fcfa + repair_fee_fcfa)
        from public.missions where created_at > v_from), 0),
    'missions_paid_on_completed_fcfa', coalesce((select sum(paid_fcfa)
        from public.missions where status = 'completed' and created_at > v_from), 0),
    'lost_fcfa',                       coalesce((select sum(travel_fee_fcfa)
        from public.missions where status in ('cancelled','refused')
          and created_at > v_from), 0),
    'missions_completed',              (select count(*) from public.missions
        where status = 'completed' and created_at > v_from),
    'missions_total',                  (select count(*) from public.missions where created_at > v_from),
    'avg_work_minutes',                coalesce((
        select round(avg(extract(epoch from (work_ended_at - work_started_at)) / 60))::int
          from public.missions
         where work_ended_at is not null and work_started_at is not null
           and created_at > v_from), 0),
    'avg_rating',                      coalesce((select round(avg(note_moyenne)::numeric, 1)
        from public.providers where note_moyenne > 0), 0),
    'open_reports',                    (select count(*) from public.provider_reports
        where status in ('open','reviewing'))
  ) into v_out;

  return v_out;
end;
$$;
grant execute on function public.admin_finance_summary(integer) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. admin_set_provider_status — Providers approuver/rejeter
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.admin_set_provider_status(
  p_provider_id uuid,
  p_status      text,
  p_reason      text default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  if p_status not in ('approved','rejected','pending') then
    raise exception 'STATUT_INVALIDE' using errcode = '22023';
  end if;

  if p_status = 'approved' then
    if exists (select 1 from public.providers
                where id = p_provider_id and identity_submitted_at is null) then
      raise exception 'IDENTITE_INCOMPLETE' using errcode = 'P0001';
    end if;
  end if;

  update public.providers
     set statut_validation = p_status,
         rejection_reason  = case when p_status = 'rejected' then left(nullif(btrim(p_reason), ''), 300) else null end,
         validated_at      = case when p_status = 'approved' then now() else validated_at end,
         validated_by      = case when p_status = 'approved' then auth.uid() else validated_by end,
         updated_at        = now()
   where id = p_provider_id;

  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  perform public.safe_notify(p_provider_id,
    case when p_status = 'approved' then 'provider_approved' else 'provider_rejected' end,
    case when p_status = 'approved' then 'Dossier approuvé' else 'Dossier rejeté' end,
    coalesce(nullif(btrim(p_reason), ''), 'Consultez l''application pour la suite.'),
    jsonb_build_object('provider_id', p_provider_id));
end;
$$;
grant execute on function public.admin_set_provider_status(uuid, text, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. admin_review_subscription — ALIAS de admin_review_subscription_request
--    (l'app appelle admin_review_subscription, le SQL de file 10 définit _request)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.admin_review_subscription(
  p_request_id uuid,
  p_approve    boolean,
  p_reason     text default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform public.admin_review_subscription_request(
    p_request_id,
    case when p_approve then 'approved' else 'rejected' end,
    p_reason);
end;
$$;
grant execute on function public.admin_review_subscription(uuid, boolean, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. admin_resolve_report — Signalements (Tour de Contrôle + Reports)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.admin_resolve_report(
  p_report  uuid,
  p_status  text,
  p_note    text default null,
  p_suspend boolean default false
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_r public.provider_reports%rowtype;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  if p_status not in ('reviewing','resolved','dismissed') then
    raise exception 'STATUT_INVALIDE' using errcode = '22023';
  end if;

  select * into v_r from public.provider_reports where id = p_report for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  update public.provider_reports
     set status      = p_status,
         admin_note  = left(nullif(btrim(p_note), ''), 1000),
         resolved_by = case when p_status = 'resolved' then auth.uid() else resolved_by end,
         resolved_at = case when p_status = 'resolved' then now() else resolved_at end
   where id = p_report;

  if p_suspend then
    update public.profiles set is_suspended = true where id = v_r.provider_id;
    perform public.safe_notify(v_r.provider_id, 'provider_suspended',
      'Compte suspendu',
      coalesce(nullif(btrim(p_note), ''), 'Votre compte a été suspendu suite à un signalement.'),
      jsonb_build_object('report_id', p_report));
  end if;
end;
$$;
grant execute on function public.admin_resolve_report(uuid, text, text, boolean) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. admin_credit_wallet — utilisé par admin_review_wallet_topup mais absent
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.admin_credit_wallet(
  p_provider uuid,
  p_amount   integer,
  p_reference text,
  p_note     text default 'Recharge'
) returns integer
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_bal integer;
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
     set balance_fcfa = public.wallets.balance_fcfa + p_amount,
         updated_at   = now()
  returning balance_fcfa into v_bal;

  insert into public.wallet_transactions
    (provider_id, kind, amount_fcfa, balance_after, reference, note, created_by)
  values
    (p_provider, 'topup', p_amount, v_bal, p_reference, p_note, auth.uid());

  return v_bal;
end;
$$;
revoke all on function public.admin_credit_wallet(uuid, integer, text, text) from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. Résolution du doublon providers_nearest
--    On garde la signature 6 args (avec vehicle_types) et on supprime la 5 args.
-- ═══════════════════════════════════════════════════════════════════════════
drop function if exists public.providers_nearest(
  double precision, double precision, text, numeric, int);

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. Résolution du conflit mission_provider_action
--    On garde UNIQUEMENT la version 2 args (file 14, prix figé catalogue).
-- ═══════════════════════════════════════════════════════════════════════════
drop function if exists public.mission_provider_action(uuid, text, integer);

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. Rajout : mission_payments.kind doit inclure 'trajet' + 'reparation' (file 14)
-- ═══════════════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from information_schema.tables
              where table_schema='public' and table_name='mission_payments') then
    alter table public.mission_payments drop constraint if exists mission_payments_kind_check;
    alter table public.mission_payments
      add constraint mission_payments_kind_check
      check (kind in ('trajet','reparation'));
  end if;
end $$;

commit;

-- ═══════════════════════════════════════════════════════════════════════════
-- Vérification finale
-- ═══════════════════════════════════════════════════════════════════════════
select proname, pg_get_function_identity_arguments(oid) as args
  from pg_proc
 where proname in (
   'admin_dashboard_stats','admin_finance_summary','admin_set_provider_status',
   'admin_review_subscription','admin_review_subscription_request',
   'admin_resolve_report','admin_credit_wallet','safe_notify','safe_notify_admins',
   'providers_nearest','mission_provider_action')
 order by proname;