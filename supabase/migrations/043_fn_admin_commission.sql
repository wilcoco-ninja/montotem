-- =============================================================================
-- 043 — RPC admin pour gérer les commissions
-- Dart : admin_commission_service.dart, admin_commission_screen.dart
-- Dépend de : 019, 010
-- =============================================================================
begin;

set local search_path to public, extensions;

create or replace function public.admin_list_commission_rules()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'service_category', service_category,
      'provider_kind', provider_kind, 'vehicle_type', vehicle_type,
      'pct', pct, 'actif', actif, 'note', note,
      'updated_at', updated_at
    ) order by service_category, provider_kind nulls first, vehicle_type nulls first)
    from public.commission_rules
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.admin_list_commission_rules() to authenticated;

create or replace function public.admin_upsert_commission_rule(
  p_id               uuid default null,
  p_service_category text default null,
  p_provider_kind    text default null,
  p_vehicle_type     text default null,
  p_pct              numeric default null,
  p_actif            boolean default true,
  p_note             text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  if p_pct is null or p_pct < 0 or p_pct > 100 then
    raise exception 'PCT_INVALIDE' using errcode = '22023';
  end if;
  if p_service_category is null or p_service_category not in (
    'ride_zemidjan','ride_tricycle_passenger','ride_tricycle_fret',
    'mission_moto','mission_tricycle','mission_voiture','mission_bus',
    'mission_camion','mission_remorquage'
  ) then
    raise exception 'SERVICE_INVALIDE' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.commission_rules
      (service_category, provider_kind, vehicle_type, pct, actif, note, updated_by)
    values
      (p_service_category, nullif(btrim(p_provider_kind), ''),
       nullif(btrim(p_vehicle_type), ''), p_pct, coalesce(p_actif, true),
       left(nullif(btrim(p_note), ''), 300), auth.uid())
    returning id into v_id;
  else
    update public.commission_rules
       set service_category = p_service_category,
           provider_kind    = nullif(btrim(p_provider_kind), ''),
           vehicle_type     = nullif(btrim(p_vehicle_type), ''),
           pct              = p_pct,
           actif            = coalesce(p_actif, actif),
           note             = left(nullif(btrim(p_note), ''), 300),
           updated_by       = auth.uid(),
           updated_at       = now()
     where id = p_id
    returning id into v_id;
  end if;
  return v_id;
end;
$$;
grant execute on function public.admin_upsert_commission_rule(
  uuid, text, text, text, numeric, boolean, text) to authenticated;

create or replace function public.admin_delete_commission_rule(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  delete from public.commission_rules where id = p_id;
end;
$$;
grant execute on function public.admin_delete_commission_rule(uuid) to authenticated;

create or replace function public.admin_commission_summary()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'courses', jsonb_build_array(
      jsonb_build_object('category','ride_zemidjan',
        'label','Zémidjan (moto 1 passager)',
        'pct', public.commission_pct('ride_zemidjan','zemidjan',null)),
      jsonb_build_object('category','ride_tricycle_passenger',
        'label','Kloboto Passager (2-3 pers.)',
        'pct', public.commission_pct('ride_tricycle_passenger','tricycle_passenger',null)),
      jsonb_build_object('category','ride_tricycle_fret',
        'label','Kloboto Colis/Bagages',
        'pct', public.commission_pct('ride_tricycle_fret','tricycle_fret',null))
    ),
    'depannage', jsonb_build_array(
      jsonb_build_object('category','mission_moto',
        'label','Dépannage moto','pct', public.commission_pct('mission_moto',null,'moto')),
      jsonb_build_object('category','mission_tricycle',
        'label','Dépannage tricycle','pct', public.commission_pct('mission_tricycle',null,'tricycle')),
      jsonb_build_object('category','mission_voiture',
        'label','Dépannage voiture','pct', public.commission_pct('mission_voiture',null,'voiture')),
      jsonb_build_object('category','mission_bus',
        'label','Dépannage bus','pct', public.commission_pct('mission_bus',null,'bus')),
      jsonb_build_object('category','mission_camion',
        'label','Dépannage camion','pct', public.commission_pct('mission_camion',null,'camion'))
    ),
    'remorquage', jsonb_build_object(
      'category','mission_remorquage',
      'label','Remorquage garage → atelier',
      'pct', public.commission_pct('mission_remorquage','garage',null))
  );
end;
$$;
grant execute on function public.admin_commission_summary() to authenticated;

commit;