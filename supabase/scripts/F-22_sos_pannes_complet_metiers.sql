-- ============================================================================
-- MonTotem — F-22 : PANNES COMPLÈTES + MÉTIERS EN COMPÉTENCES + MATCHING
-- ============================================================================
-- Objectif : quand un véhicule est en panne sur la route, il doit toujours
-- y avoir un réparateur prêt à intervenir.
--
-- 1. SIX nouvelles pannes quotidiennes des routes africaines :
--      CARBURANT_EPUISE        panne sèche (plus d'essence)
--      FREIN_MOTO              freins défaillants deux-trois roues
--      ECLAIRAGE_CLAXON        éclairage / klaxon / clignotants HS
--      FUITE_HUILE             fuite d'huile ou de carburant
--      ROUE_DEJANTEE           roue déjantée / jante voilée
--      SUSPENSION_AMORTISSEUR  suspension / amortisseur cassé
--
-- 2. Nouvelle compétence LIVRAISON_CARBURANT (vendeur de carburant mobile).
--
-- 3. À L'INSCRIPTION (et à chaque mise à jour du catalogue), les savoir-
--    faire du pro sont traduits automatiquement en langage SOS :
--      vehicle_types → sos vehicle_categories (ZEM_MOTO, E_CAR, …)
--      métier        → sos_services + habilitations + compétences
--    (compétences insérées en attente de validation admin).
--
-- 4. Rattrapage immédiat des prestataires DÉJÀ inscrits (même dérivation).
--
-- 5. Matching assoupli : un pro sans la pièce en stock N'EST PLUS exclu —
--    il est proposé après ceux qui l'ont (il l'achète en chemin). Il y a
--    donc toujours un réparateur proposé quand un pro compétent existe.
--
-- Exécution : Supabase SQL Editor (après sos/01..09, F-21). Idempotent.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Nouvelle compétence : livraison de carburant express
-- ---------------------------------------------------------------------------
insert into sos_competences (code, libelle)
values ('LIVRAISON_CARBURANT', 'Livraison de carburant express (panne sèche)')
on conflict (code) do update set libelle = excluded.libelle;

-- ---------------------------------------------------------------------------
-- 2. Les six nouvelles pannes
-- ---------------------------------------------------------------------------
insert into sos_pannes (code, libelle, description, main_oeuvre_fcfa,
                        piece_obligatoire, piece_code, piece_libelle, position)
values
  ('CARBURANT_EPUISE', 'Panne sèche : plus d''essence / carburant épuisé',
   'Le dépanneur arrive avec un bidon d''essence homologué.', 2000, false,
   null, null, 47),
  ('FREIN_MOTO', 'Freins défaillants (moto, scooter, tricycle)',
   'Garnitures, câble ou circuit de frein.', 3500, false,
   'GARNITURE_FREIN_MOTO', 'Garnitures / plaquettes de frein', 48),
  ('ECLAIRAGE_CLAXON', 'Éclairage, klaxon ou clignotants en panne',
   'Ampoules, fusibles, faisceau, klaxon.', 2500, false,
   'AMPOULE_FUSIBLE', 'Ampoule / fusible / faisceau', 49),
  ('FUITE_HUILE', 'Fuite d''huile ou de carburant',
   'Recherche de fuite, joints et resserrage.', 4000, false,
   'JOINT_MOTO', 'Joints / visserie moteur', 50),
  ('ROUE_DEJANTEE', 'Roue déjantée / jante voilée',
   'Déjantage, redressage ou remplacement de jante.', 3000, false,
   null, null, 51),
  ('SUSPENSION_AMORTISSEUR', 'Suspension / amortisseur cassé',
   'Amortisseur, silentbloc ou fourche.', 5000, false,
   'AMORTISSEUR_PIECE', 'Amortisseur / silentbloc', 52)
on conflict (code) do update
  set libelle           = excluded.libelle,
      description       = excluded.description,
      main_oeuvre_fcfa  = excluded.main_oeuvre_fcfa,
      piece_obligatoire = excluded.piece_obligatoire,
      piece_code        = excluded.piece_code,
      piece_libelle     = excluded.piece_libelle,
      position          = excluded.position;

-- Matrice panne ↔ véhicule
insert into sos_panne_vehicules (panne_code, vehicule_code)
select g.panne_code, vt.vehicule
from (values
  ('CARBURANT_EPUISE', array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET',
                             'CAR_THERM','UTILITAIRE_VAN','MINIBUS','BUS_TRANSPORT',
                             'CAMION_6_ROUES','CAMION_10_ROUES','SEMI_REMORQUE']),
  ('FREIN_MOTO',       array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET',
                             'E_MOTO','E_SCOOTER']),
  ('ECLAIRAGE_CLAXON', array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET',
                             'CAR_THERM','UTILITAIRE_VAN','MINIBUS','BUS_TRANSPORT']),
  ('FUITE_HUILE',      array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET',
                             'CAR_THERM','UTILITAIRE_VAN','MINIBUS']),
  ('ROUE_DEJANTEE',    array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET']),
  ('SUSPENSION_AMORTISSEUR', array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX',
                             'KLOBOTO_FRET','CAR_THERM','UTILITAIRE_VAN','MINIBUS'])
) as g(panne_code, vehicules)
cross join lateral unnest(g.vehicules) as vt(vehicule)
join sos_vehicules v on v.code = vt.vehicule
on conflict (panne_code, vehicule_code) do nothing;

-- Matrice panne ↔ compétences (le métier qu'il faut pour réparer)
insert into sos_panne_competences (panne_code, skill_code)
values
  ('CARBURANT_EPUISE',       'LIVRAISON_CARBURANT'),
  ('CARBURANT_EPUISE',       'MECANIQUE_MOTO'),
  ('CARBURANT_EPUISE',       'MECANIQUE_VL'),
  ('CARBURANT_EPUISE',       'MECA_LOURDE_PL'),
  ('FREIN_MOTO',             'MECANIQUE_MOTO'),
  ('ECLAIRAGE_CLAXON',       'ELEC_AUTO'),
  ('ECLAIRAGE_CLAXON',       'MECANIQUE_MOTO'),
  ('FUITE_HUILE',            'MECANIQUE_MOTO'),
  ('FUITE_HUILE',            'MECANIQUE_VL'),
  ('ROUE_DEJANTEE',          'PNEU_MOTO'),
  ('SUSPENSION_AMORTISSEUR', 'MECANIQUE_MOTO'),
  ('SUSPENSION_AMORTISSEUR', 'MECANIQUE_VL')
on conflict (panne_code, skill_code) do nothing;

-- Matrice panne ↔ services de prestation express
insert into sos_panne_services (panne_code, service_code)
values
  ('CARBURANT_EPUISE',       'ATELIER_MOBILE_LEGER'),
  ('FREIN_MOTO',             'ATELIER_MOBILE_LEGER'),
  ('ECLAIRAGE_CLAXON',       'ATELIER_MOBILE_LEGER'),
  ('FUITE_HUILE',            'ATELIER_MOBILE_LEGER'),
  ('ROUE_DEJANTEE',          'VULCANISATEUR_EXPRESS'),
  ('SUSPENSION_AMORTISSEUR', 'ATELIER_MOBILE_LEGER'),
  ('SUSPENSION_AMORTISSEUR', 'GARAGE_MECANIQUE')
on conflict (panne_code, service_code) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Traduction vehicle_types → catégories SOS (réutilisable)
-- ---------------------------------------------------------------------------
create or replace function public.sos_categories_from_types(p_types text[])
returns text[]
language sql
immutable
as $func$
  select coalesce(array_agg(distinct u.cat), '{}'::text[])
  from unnest(coalesce(p_types, '{}'::text[])) as t(ty)
  cross join lateral (values
    ('moto',     array['ZEM_MOTO','SCOOTER_THERM','E_MOTO','E_SCOOTER']),
    ('tricycle', array['CLOBOTO_PAX','KLOBOTO_FRET']),
    ('voiture',  array['CAR_THERM','E_CAR','UTILITAIRE_VAN']),
    ('bus',      array['MINIBUS','BUS_TRANSPORT']),
    ('camion',   array['CAMION_6_ROUES','CAMION_10_ROUES','SEMI_REMORQUE'])
  ) as m(ty, cats)
  cross join lateral unnest(m.cats) as u(cat)
  where t.ty = m.ty;
$func$;

-- ---------------------------------------------------------------------------
-- 4. À l'inscription / mise à jour du catalogue : le savoir-faire du pro
--    est enregistré en langage SOS (catégories, services, habilitations,
--    compétences). Même signature et mêmes règles que le script 031 :
--    uniquement l'enregistrement SOS ajouté à la fin.
-- ---------------------------------------------------------------------------
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

  -- SOS : traduire le savoir-faire déclaré en codes officiels -----------
  perform public.sync_provider_sos_profile(v_uid);
end;
$$;
revoke all on function public.set_provider_catalog(
  text[], jsonb, integer, integer, integer, text) from public, anon;
grant execute on function public.set_provider_catalog(
  text[], jsonb, integer, integer, integer, text) to authenticated;

-- La traduction elle-même (réutilisée pour le rattrapage des anciens pros).
create or replace function public.sync_provider_sos_profile(p_provider uuid)
returns void
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_metier text;
  v_services text[] := '{}';
  v_hab      text[] := '{}';
begin
  select metier, vehicle_types into v_metier
  from providers where id = p_provider;
  if v_metier is null then return; end if;

  -- Catégories de véhicules SOS déduites des types de véhicules.
  update providers
     set vehicle_categories = sos_categories_from_types(vehicle_types)
   where id = p_provider;

  -- Services express, habilitations et compétences selon le métier.
  v_services := case v_metier
    when 'Mécanicien'               then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
    when 'Service garage'           then array['GARAGE_MECANIQUE']
    when 'Vulcanisateur pneu'       then array['VULCANISATEUR_EXPRESS']
    when 'Électricien auto & moto'  then array['ATELIER_MOBILE_LEGER','TECH_ELECTRIQUE']
    when 'Dépanneuse / Remorquage'  then array['DEPANNEUSE_VL','DEPANNEUSE_PL']
    when 'Vendeur de carburant'     then array['ATELIER_MOBILE_LEGER']
    else '{}'::text[]
  end;
  v_hab := case v_metier
    when 'Électricien auto & moto' then array['HAB_ELECTRIQUE']
    when 'Dépanneuse / Remorquage' then array['HAB_DEPANNEUSE_VL','HAB_DEPANNEUSE_PL']
    else '{}'::text[]
  end;

  update providers
     set sos_services  = v_services,
         habilitations = v_hab
   where id = p_provider;

  -- Compétences : en attente de validation admin (valide = false).
  insert into provider_skill_codes (provider_id, skill_code)
  select p_provider, s.skill_code
  from (values
    ('Mécanicien',              array['MECANIQUE_MOTO','MECANIQUE_VL']),
    ('Service garage',          array['MECANIQUE_MOTO','MECANIQUE_VL']),
    ('Vulcanisateur pneu',      array['PNEU_MOTO','PNEU_VL']),
    ('Électricien auto & moto', array['ELEC_AUTO','ELEC_VEHICULE_HAB','SWAP_BATTERIE']),
    ('Dépanneuse / Remorquage', array['REMORQUAGE_VL','REMORQUAGE_PL']),
    ('Vendeur de carburant',    array['LIVRAISON_CARBURANT'])
  ) as m(metier, skills)
  cross join lateral unnest(m.skills) as s(skill_code)
  where m.metier = v_metier
  on conflict (provider_id, skill_code) do nothing;
end;
$func$;
revoke all on function public.sync_provider_sos_profile(uuid) from public, anon;
grant execute on function public.sync_provider_sos_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Rattrapage des prestataires DÉJÀ inscrits : ils deviennent
--    immédiatement trouvables par le diagnostic SOS.
-- ---------------------------------------------------------------------------
update providers p
   set vehicle_categories = sos_categories_from_types(p.vehicle_types),
       sos_services  = case p.metier
         when 'Mécanicien'               then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
         when 'Service garage'           then array['GARAGE_MECANIQUE']
         when 'Vulcanisateur pneu'       then array['VULCANISATEUR_EXPRESS']
         when 'Électricien auto & moto'  then array['ATELIER_MOBILE_LEGER','TECH_ELECTRIQUE']
         when 'Dépanneuse / Remorquage'  then array['DEPANNEUSE_VL','DEPANNEUSE_PL']
         when 'Vendeur de carburant'     then array['ATELIER_MOBILE_LEGER']
         else '{}'::text[]
       end,
       habilitations = case p.metier
         when 'Électricien auto & moto' then array['HAB_ELECTRIQUE']
         when 'Dépanneuse / Remorquage' then array['HAB_DEPANNEUSE_VL','HAB_DEPANNEUSE_PL']
         else '{}'::text[]
       end
 where p.metier in ('Mécanicien', 'Vulcanisateur pneu', 'Électricien auto & moto',
                    'Station d''essence', 'Service garage', 'Dépanneuse / Remorquage',
                    'Vendeur de carburant', 'Lavage auto & moto');

insert into provider_skill_codes (provider_id, skill_code)
select p.id, s.skill_code
from providers p
join (values
  ('Mécanicien',              array['MECANIQUE_MOTO','MECANIQUE_VL']),
  ('Service garage',          array['MECANIQUE_MOTO','MECANIQUE_VL']),
  ('Vulcanisateur pneu',      array['PNEU_MOTO','PNEU_VL']),
  ('Électricien auto & moto', array['ELEC_AUTO','ELEC_VEHICULE_HAB','SWAP_BATTERIE']),
  ('Dépanneuse / Remorquage', array['REMORQUAGE_VL','REMORQUAGE_PL']),
  ('Vendeur de carburant',    array['LIVRAISON_CARBURANT'])
) as m(metier, skills) on m.metier = p.metier
cross join lateral unnest(m.skills) as s(skill_code)
on conflict (provider_id, skill_code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. Matching assoupli : PLUS JAMAIS de route sans réparateur.
--    Un pro compétent sans la pièce en stock est proposé APRÈS ceux qui
--    l'ont (il achète la pièce en chemin) au lieu d'être exclu.
-- ---------------------------------------------------------------------------
create or replace function sos_match_providers(
  p_vehicule text,
  p_panne    text,
  p_lat      double precision,
  p_lng      double precision,
  p_rayon_km numeric default 15,
  p_limit    int    default 5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $func$
declare
  v_vehicule   text := upper(btrim(p_vehicule));
  v_panne      text := upper(btrim(p_panne));
  v_existe     boolean;
  v_piece_code text;
  v_comp       text[];
  v_hab        text[];
  v_services   text[];
begin
  select true into v_existe
  from sos_pannes p
  join sos_panne_vehicules pv on pv.panne_code = p.code
  where p.code = v_panne and pv.vehicule_code = v_vehicule
  limit 1;

  if v_existe is null then
    raise exception 'PANNE_INCOMPATIBLE : la panne % n''est pas autorisée pour le véhicule %',
      v_panne, v_vehicule;
  end if;

  select piece_code into v_piece_code
  from sos_pannes where code = v_panne;

  select coalesce(array_agg(distinct c.skill_code), '{}') into v_comp
  from sos_panne_competences c
  where c.panne_code = v_panne;

  select coalesce(array_agg(distinct h), '{}') into v_hab
  from (
    select unnest(s.habilitations) as h
    from sos_panne_services ps
    join sos_services s on s.code = ps.service_code
    where ps.panne_code = v_panne
  ) hab;

  select coalesce(array_agg(distinct ps.service_code), '{}') into v_services
  from sos_panne_services ps
  where ps.panne_code = v_panne;

  return coalesce(jsonb_agg(
    jsonb_build_object(
      'id',            t.id,
      'nom',           t.nom,
      'business_name', t.business_name,
      'metier',        t.metier,
      'telephone',     t.telephone,
      'note_moyenne',  t.note_moyenne,
      'distance_km',   t.distance_km,
      'rayon_max_km',  t.rayon_max_km,
      'sos_services',  to_jsonb(t.services_match),
      'habilitations', to_jsonb(t.habilitations),
      'competences',   to_jsonb(t.competences),
      'devis', jsonb_build_object(
        'main_oeuvre_fcfa', t.mo_fcfa,
        'piece_code',       v_piece_code,
        'piece_libelle',    t.piece_libelle,
        'piece_prix_fcfa',  t.piece_prix,
        'piece_stock',      t.piece_stock,
        'deplacement_fcfa', t.deplacement_fcfa,
        'total_fcfa',       t.total_fcfa,
        'tarif_km_garanti', t.tarif_km_fcfa
      )
    )
    order by t.a_la_piece asc, t.total_fcfa asc, t.distance_km asc
  ) filter (where t.id is not null), '[]'::jsonb)
  from (
    select
      p.id,
      p.business_name as nom,
      p.business_name,
      p.metier,
      prof.phone as telephone,
      p.note_moyenne,
      p.rayon_max_km,
      p.tarif_km_fcfa,
      p.habilitations,
      p.sos_services as services_match,
      haversine_km(p.latitude, p.longitude, p_lat, p_lng) as distance_km,
      pn.main_oeuvre_fcfa as mo_fcfa,
      piece.prix_fcfa     as piece_prix,
      piece.stock         as piece_stock,
      piece.libelle       as piece_libelle,
      (case when coalesce(piece.stock, 0) > 0 then 0 else 1 end) as a_la_piece,
      greatest(
        p.frais_deplacement_min_fcfa,
        ceil(p.tarif_km_fcfa
             * least(
                 haversine_km(p.latitude, p.longitude, p_lat, p_lng),
                 p.rayon_max_km::numeric
               ) / 50.0)::int * 50
      )::int as deplacement_fcfa,
      (
        pn.main_oeuvre_fcfa
        + coalesce(piece.prix_fcfa, 0)
        + greatest(
            p.frais_deplacement_min_fcfa,
            ceil(p.tarif_km_fcfa
                 * least(
                     haversine_km(p.latitude, p.longitude, p_lat, p_lng),
                     p.rayon_max_km::numeric
                   ) / 50.0)::int * 50
          )::int
      ) as total_fcfa,
      (
        select array_agg(distinct s.skill_code)
        from provider_skill_codes s
        where s.provider_id = p.id
          and s.valide
          and s.skill_code = any (v_comp)
      ) as competences
    from providers p
    join sos_pannes pn on pn.code = v_panne
    left join profiles prof on prof.id = p.id
    left join lateral (
      select ci.prix_fcfa, ci.stock, ci.piece_libelle as libelle
      from provider_catalog_items ci
      where ci.provider_id = p.id
        and ci.piece_code  = v_piece_code
        and ci.prix_fcfa is not null
        and ci.stock > 0
      order by ci.prix_fcfa asc
      limit 1
    ) piece on true
    where p.disponible is true
      and p.statut_validation = 'approved'
      and not exists (
        select 1 from profiles pf
        where pf.id = p.id and pf.is_suspended
      )
      and not exists (
        select 1 from wallets w
        where w.provider_id = p.id and w.blocked
      )
      and p.vehicle_categories @> array[v_vehicule]
      and p.habilitations @> coalesce(v_hab, '{}'::text[])
      and p.sos_services && coalesce(v_services, '{}'::text[])
      and exists (
        select 1 from provider_skill_codes s
        where s.provider_id = p.id and s.valide and s.skill_code = any (v_comp)
      )
      and haversine_km(p.latitude, p.longitude, p_lat, p_lng)
            <= least(p_rayon_km, p.rayon_max_km::numeric)
    order by
      haversine_km(p.latitude, p.longitude, p_lat, p_lng) asc
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  ) t;
end;
$func$;

revoke all on function sos_match_providers(text, text, double precision, double precision, numeric, int) from public;
grant execute on function sos_match_providers(text, text, double precision, double precision, numeric, int)
  to anon, authenticated;

commit;
