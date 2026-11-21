-- =============================================================================
-- 042 — RPC admin pour les courses
-- Dart : admin_ride_service.dart, admin_rides_screen.dart
-- Dépend de : 017, 037
-- =============================================================================
begin;

set local search_path to public, extensions;

create or replace function public.admin_rides(p_limit integer default 150)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  r     public.rides%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  update public.rides
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Aucun conducteur disponible'
   where status = 'requested' and created_at < now() - interval '30 minutes';
  for r in
    select * from public.rides order by created_at desc
     limit least(greatest(coalesce(p_limit, 150), 1), 500)
  loop
    v_out := v_out || jsonb_build_array(public.ride_build_json(r, auth.uid(), true));
  end loop;
  return v_out;
end;
$$;
grant execute on function public.admin_rides(integer) to authenticated;

create or replace function public.admin_cancel_ride(p_ride uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_r      public.rides%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  if char_length(v_reason) < 3 then
    raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
  end if;
  select * into v_r from public.rides where id = p_ride for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;
  if v_r.status in ('completed','cancelled') then
    raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
  end if;
  update public.rides
     set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
         cancel_reason = left(v_reason, 300)
   where id = v_r.id;
  perform public.safe_notify(v_r.client_id, 'ride_cancelled',
    'Course annulée', 'Annulée par MONTOTEM : ' || left(v_reason, 120),
    jsonb_build_object('ride_id', v_r.id));
  if v_r.provider_id is not null then
    perform public.safe_notify(v_r.provider_id, 'ride_cancelled',
      'Course annulée', 'Annulée par MONTOTEM : ' || left(v_reason, 120),
      jsonb_build_object('ride_id', v_r.id));
  end if;
end;
$$;
grant execute on function public.admin_cancel_ride(uuid, text) to authenticated;

commit;