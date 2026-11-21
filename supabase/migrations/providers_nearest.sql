create or replace function public.providers_nearest(
  p_lat double precision, p_lng double precision,
  p_kind text default null, p_radius_km numeric default 3, p_limit int default 3
) returns table (
  id uuid, business_name text, provider_kind text, distance_m int,
  eta_min int, travel_fee_fcfa int, telephone text, note_moyenne numeric)
language sql stable security definer set search_path = public, extensions
as $$
  with me as (select ST_SetSRID(ST_MakePoint(p_lng,p_lat),4326)::geography g)
  select pv.id, pv.business_name, pv.provider_kind,
         round(ST_Distance(pv.location, me.g))::int,
         greatest(ceil(ST_Distance(pv.location, me.g)*1.25/1000/25*60)::int, 1),
         greatest(ceil(ST_Distance(pv.location, me.g)*1.25/1000*pv.tarif_km_fcfa/50.0)::int*50,
                  pv.frais_deplacement_min_fcfa),
         case when auth.uid() is not null then pf.phone end,
         pv.note_moyenne
    from public.providers pv
    join public.profiles pf on pf.id = pv.id, me
   where pv.statut_validation='approved' and pv.fin_abonnement > now()
     and pv.disponible and not pf.is_suspended
     and not exists (select 1 from public.wallets w where w.provider_id=pv.id and w.blocked)
     and (p_kind is null or pv.provider_kind = p_kind)
     and ST_DWithin(pv.location, me.g, p_radius_km*1000)
   order by ST_Distance(pv.location, me.g)
   limit least(p_limit, 20);
$$;
grant execute on function public.providers_nearest(double precision,double precision,text,numeric,int)
  to anon, authenticated;