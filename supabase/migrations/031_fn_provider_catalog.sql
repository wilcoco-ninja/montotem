-- =============================================================================
-- 031 — Catalogue : lire + modifier (prestation × véhicule × prix)
-- Dart : provider_catalog_service.dart (obtenirFiche, enregistrer)
-- Dépend de : 014, 019
-- =============================================================================
begin;

set local search_path to public, extensions;

-- RPC publique : fiche d'un prestataire
create or replace function public.provider_public_catalog(p_provider uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_pv public.providers%rowtype;
begin
  select pv.* into v_pv
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.id = p_provider
     and pv.statut_validation = 'approved'
     and not pf.is_suspended;
  if not found then return null; end if;

  return jsonb_build_object(
    'vehicle_types', to_jsonb(v_pv.vehicle_types),
    'skills', coalesce((
        select jsonb_agg(s.label order by s.created_at)
          from public.provider_skills s where s.provider_id = p_provider
      ), '[]'::jsonb),
    'tarif_km_fcfa', v_pv.tarif_km_fcfa,
    'frais_deplacement_min_fcfa', v_pv.frais_deplacement_min_fcfa,
    'rayon_max_km', v_pv.rayon_max_km,
    'accepte_mobile_money', (v_pv.momo_numero is not null and v_pv.momo_operateur is not null),
    'services', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', i.id,
          'nom', i.nom,
          'categorie_vehicule', i.categorie_vehicule,
          'prix_fcfa', i.prix_fcfa)
          order by i.categorie_vehicule, i.created_at, i.id)
          from public.provider_catalog_items i where i.provider_id = p_provider
      ), '[]'::jsonb),
    'id_document_type', v_pv.id_document_type,
    'photo_garage_url', v_pv.photo_garage_url,
    'garage_description', v_pv.garage_description
  );
end;
$$;
revoke all on function public.provider_public_catalog(uuid) from public;
grant execute on function public.provider_public_catalog(uuid) to anon, authenticated;

-- RPC prestataire : remplacer en bloc son catalogue
create or replace function public.set_provider_catalog(
  p_vehicle_types text[],
  p_services      jsonb,
  p_tarif_km      integer,
  p_frais_min     integer,
  p_rayon_km      integer,
  p_whatsapp      text default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_item jsonb;
  v_nom  text;
  v_cat  text;
  v_prix integer;
  v_id   uuid;
  v_keep uuid[] := '{}';
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if not exists (select 1 from public.providers where id = v_uid) then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;

  if p_vehicle_types is null
     or cardinality(p_vehicle_types) = 0
     or not (p_vehicle_types <@ array['moto','tricycle','voiture','bus','camion']::text[]) then
    raise exception 'VEHICULES_OBLIGATOIRES' using errcode = '22023';
  end if;
  if p_services is null
     or jsonb_typeof(p_services) <> 'array'
     or jsonb_array_length(p_services) = 0
     or jsonb_array_length(p_services) > 60 then
    raise exception 'SERVICES_OBLIGATOIRES' using errcode = '22023';
  end if;
  if p_tarif_km is null or p_tarif_km not between 0 and 5000
     or p_frais_min is null or p_frais_min not between 0 and 100000
     or p_rayon_km is null or p_rayon_km not between 1 and 50 then
    raise exception 'TARIF_INVALIDE' using errcode = '22023';
  end if;

  for v_item in select * from jsonb_array_elements(p_services) loop
    v_nom := left(regexp_replace(btrim(coalesce(v_item ->> 'nom', '')), '\s+', ' ', 'g'), 80);
    v_cat := v_item ->> 'categorie_vehicule';

    if char_length(v_nom) < 2
       or v_cat is null or not (v_cat = any (p_vehicle_types)) then
      raise exception 'SERVICE_INVALIDE' using errcode = '22023';
    end if;

    begin
      v_prix := (v_item ->> 'prix_fcfa')::integer;
    exception when others then v_prix := null;
    end;
    if v_prix is null or v_prix <= 0 or v_prix > 10000000 then
      raise exception 'TARIF_INVALIDE' using errcode = '22023';
    end if;

    insert into public.provider_catalog_items
      (provider_id, nom, categorie_vehicule, prix_fcfa)
    values (v_uid, v_nom, v_cat, v_prix)
    on conflict (provider_id, lower(nom), categorie_vehicule)
    do update set prix_fcfa = excluded.prix_fcfa, nom = excluded.nom
    returning id into v_id;

    v_keep := v_keep || v_id;
  end loop;

  delete from public.provider_catalog_items
   where provider_id = v_uid and id <> all (v_keep);

  update public.providers
     set vehicle_types = (select array_agg(distinct x order by x)
                            from unnest(p_vehicle_types) as x),
         tarif_km_fcfa = p_tarif_km,
         frais_deplacement_min_fcfa = p_frais_min,
         rayon_max_km  = p_rayon_km,
         whatsapp      = left(nullif(btrim(regexp_replace(coalesce(p_whatsapp,''),
                          '[^0-9+ ]', '', 'g')), ''), 20)
   where id = v_uid;
end;
$$;
revoke all on function public.set_provider_catalog(
  text[], jsonb, integer, integer, integer, text) from public, anon;
grant execute on function public.set_provider_catalog(
  text[], jsonb, integer, integer, integer, text) to authenticated;

commit;