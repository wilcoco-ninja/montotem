begin;

set local search_path to public, extensions;

-- 1. Nettoyage préalable pour éviter les conflits
drop function if exists public.admin_dashboard_stats();
drop function if exists public.admin_finance_summary(integer);
drop function if exists public.admin_set_provider_status(uuid, text, text);
drop function if exists public.admin_resolve_report(uuid, text, text, boolean);

-- 2. Statistiques du tableau de bord admin
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'total_users',        (select count(*) from public.profiles where role <> 'admin'),
    'total_providers',    (select count(*) from public.providers where statut_validation = 'approved'),
    'pending_providers',  (select count(*) from public.providers where statut_validation = 'pending'),
    'pending_payments',   (select count(*) from public.wallet_topup_requests
                            where statut = 'awaiting_validation'),
    'active_requests',    (select count(*) from public.missions
                            where status in ('pending','accepted','arrived','working'))
                          + (select count(*) from public.rides
                            where status in ('requested','accepted','arrived','in_progress')),
    'completed_requests', (select count(*) from public.missions where status = 'completed')
                          + (select count(*) from public.rides where status = 'completed'),
    'open_reports',       (select count(*) from public.provider_reports
                            where status in ('open','reviewing')),
    'revenue_30d_fcfa',   coalesce((
        select -sum(amount_fcfa) from public.wallet_transactions
         where kind in ('commission_cash','commission_momo','commission_travel')
           and created_at > now() - interval '30 days'), 0)
  );
end;
$$;
grant execute on function public.admin_dashboard_stats() to authenticated;

-- 3. Résumé financier
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
      select jsonb_agg(jsonb_build_object(
        'day', to_char(d, 'DD/MM'), 'income', coalesce(s, 0)) order by d)
        from (
          select date_trunc('day', g)::date as d,
                 (select coalesce(-sum(amount_fcfa), 0)
                    from public.wallet_transactions t
                   where t.kind in ('commission_cash','commission_momo','commission_travel')
                     and t.created_at::date = g::date) as s
            from generate_series(v_from::date, now()::date, interval '1 day') g
        ) x
    ), '[]'::jsonb),
    'commission_ride_zemidjan',          coalesce((select -sum(amount_fcfa)
        from public.wallet_transactions
       where kind in ('commission_cash','commission_momo')
         and note like '%ride_zemidjan%'
         and created_at > v_from), 0),
    'commission_ride_tricycle_passenger', coalesce((select -sum(amount_fcfa)
        from public.wallet_transactions
       where kind in ('commission_cash','commission_momo')
         and note like '%ride_tricycle_passenger%'
         and created_at > v_from), 0),
    'commission_ride_tricycle_fret',      coalesce((select -sum(amount_fcfa)
        from public.wallet_transactions
       where kind in ('commission_cash','commission_momo')
         and note like '%ride_tricycle_fret%'
         and created_at > v_from), 0),
    'commission_mission_total',            coalesce((select -sum(amount_fcfa)
        from public.wallet_transactions
       where kind = 'commission_travel'
         and created_at > v_from), 0),
    'rides_completed',   (select count(*) from public.rides
                          where status = 'completed' and completed_at > v_from),
    'rides_volume_fcfa', coalesce((select sum(final_fare_fcfa) from public.rides
                                  where status = 'completed' and completed_at > v_from), 0),
    'missions_completed',(select count(*) from public.missions
                          where status = 'completed' and work_ended_at > v_from),
    'missions_total',    (select count(*) from public.missions where created_at > v_from),
    'wallet_debt_fcfa',  coalesce((select sum(-balance_fcfa) from public.wallets
                                    where balance_fcfa < 0), 0),
    'providers_blocked', (select count(*) from public.wallets where blocked)
  ) into v_out;
  return v_out;
end;
$$;
grant execute on function public.admin_finance_summary(integer) to authenticated;

-- 4. Définir le statut d'un prestataire (admin)
create or replace function public.admin_set_provider_status(
  p_provider_id uuid, p_status text, p_reason text default null
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
  if p_status = 'approved' and exists (
    select 1 from public.providers
     where id = p_provider_id and identity_submitted_at is null) then
    raise exception 'IDENTITE_INCOMPLETE' using errcode = 'P0001';
  end if;
  update public.providers
     set statut_validation = p_status,
         rejection_reason  = case when p_status = 'rejected'
                                  then left(nullif(btrim(p_reason), ''), 300)
                                  else null end,
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

-- 5. Résoudre un signalement (admin)
create or replace function public.admin_resolve_report(
  p_report uuid, p_status text, p_note text default null, p_suspend boolean default false
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
     set status = p_status,
         admin_note = left(nullif(btrim(p_note), ''), 1000),
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

commit;