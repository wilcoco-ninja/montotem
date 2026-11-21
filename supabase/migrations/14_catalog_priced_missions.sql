-- =============================================================================
-- MONTOTEM : 14 - Tunnel de commande à prix fixes (catalogue -> mission -> paiement)
-- Prérequis : scripts 01b à 10 et 12 exécutés.
-- Idempotent. À exécuter dans le SQL Editor Supabase, en une seule fois.
--
-- Ce que fait ce script
--   1. Catalogue : supprime le mode « sur devis » (plus aucune négociation).
--      Chaque prestation a UN prix fixe et un identifiant stable.
--   2. Missions : une commande choisit des prestations du catalogue du
--      prestataire. Le prix est figé au moment de la commande (mission_items).
--   3. Supprime la saisie libre du prix de réparation par le prestataire.
--   4. Le prestataire ne peut accepter qu'une demande dont le déplacement est
--      déjà payé en Mobile Money (déclaré avec sa référence).
--   5. Supprime les anciennes fonctions create_mission / mission_provider_action.
-- =============================================================================
begin;

set local search_path to public, extensions;

-- -----------------------------------------------------------------------------
-- 1. Catalogue : prix fixe obligatoire, identifiant stable
-- -----------------------------------------------------------------------------
do $$
declare
  v_n integer := 0;
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public'
                and table_name = 'provider_catalog_items'
                and column_name = 'mode_prix') then
    -- Une prestation « sur devis » ne peut pas être commandée sans négociation.
    delete from public.provider_catalog_items
     where mode_prix = 'devis' or prix_fcfa is null;
    get diagnostics v_n = row_count;
  end if;
  raise notice 'Prestations sur devis supprimées : % (les prestataires concernés doivent leur donner un prix)', v_n;
end $$;

alter table public.provider_catalog_items
  drop constraint if exists catalog_items_price_consistency;
alter table public.provider_catalog_items
  drop column if exists mode_prix;
alter table public.provider_catalog_items
  alter column prix_fcfa set not null;

-- Doublons (même nom + même véhicule) : on garde le plus ancien.
delete from public.provider_catalog_items a
 using public.provider_catalog_items b
 where a.provider_id = b.provider_id
   and lower(a.nom) = lower(b.nom)
   and a.categorie_vehicule = b.categorie_vehicule
   and (a.created_at, a.id) > (b.created_at, b.id);

create unique index if not exists uq_catalog_items_nom
  on public.provider_catalog_items (provider_id, lower(nom), categorie_vehicule);

-- Fiche publique : prestations avec id + prix fixe, et moyen de paiement.
create or replace function public.provider_public_catalog(p_provider uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_pv public.providers%rowtype;
begin
  select pv.* into v_pv
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.id = p_provider
     and pv.statut_validation = 'approved'
     and pv.fin_abonnement > now()
     and not pf.is_suspended;
  if not found then
    return null;
  end if;

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
        select jsonb_agg(
                 jsonb_build_object(
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

-- Catalogue du prestataire connecté : mise à jour SANS changer les identifiants
-- (une commande en cours de saisie reste valable si le prestataire modifie un prix).
create or replace function public.set_provider_catalog(
  p_vehicle_types text[],
  p_services      jsonb,
  p_tarif_km      integer,
  p_frais_min     integer,
  p_rayon_km      integer,
  p_whatsapp      text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
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
     or not (p_vehicle_types <@ array['moto', 'voiture', 'camion']::text[]) then
    raise exception 'VEHICULES_OBLIGATOIRES' using errcode = '22023';
  end if;

  if p_services is null
     or jsonb_typeof(p_services) <> 'array'
     or jsonb_array_length(p_services) = 0
     or jsonb_array_length(p_services) > 60 then
    raise exception 'SERVICES_OBLIGATOIRES' using errcode = '22023';
  end if;

  if p_tarif_km  is null or p_tarif_km  not between 0 and 5000
     or p_frais_min is null or p_frais_min not between 0 and 100000
     or p_rayon_km  is null or p_rayon_km  not between 1 and 50 then
    raise exception 'TARIF_INVALIDE' using errcode = '22023';
  end if;

  for v_item in select * from jsonb_array_elements(p_services) loop
    v_nom := left(regexp_replace(btrim(coalesce(v_item ->> 'nom', '')), '\s+', ' ', 'g'), 80);
    v_cat := v_item ->> 'categorie_vehicule';

    if char_length(v_nom) < 2
       or v_cat is null or not (v_cat = any (p_vehicle_types)) then
      raise exception 'SERVICE_INVALIDE' using errcode = '22023';
    end if;

    -- Plus de « sur devis » : un prix fixe est obligatoire.
    begin
      v_prix := (v_item ->> 'prix_fcfa')::integer;
    exception when others then
      v_prix := null;
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
     set vehicle_types = (select array_agg(distinct x order by x) from unnest(p_vehicle_types) as x),
         tarif_km_fcfa = p_tarif_km,
         frais_deplacement_min_fcfa = p_frais_min,
         rayon_max_km  = p_rayon_km,
         whatsapp      = left(nullif(btrim(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9+ ]', '', 'g')), ''), 20)
   where id = v_uid;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. Lignes de commande : prestations choisies, prix figés
-- -----------------------------------------------------------------------------
create table if not exists public.mission_items (
  id              uuid primary key default gen_random_uuid(),
  mission_id      uuid not null references public.missions (id) on delete cascade,
  catalog_item_id uuid references public.provider_catalog_items (id) on delete set null,
  nom             text not null,
  prix_fcfa       integer not null check (prix_fcfa > 0),
  created_at      timestamptz not null default now()
);

create index if not exists idx_mission_items_mission
  on public.mission_items (mission_id);

alter table public.mission_items enable row level security;

drop policy if exists mission_items_select on public.mission_items;
create policy mission_items_select on public.mission_items
  for select to authenticated
  using (
    exists (select 1 from public.missions m
             where m.id = mission_items.mission_id
               and (m.client_id = (select auth.uid())
                    or m.provider_id = (select auth.uid())))
    or public.is_admin()
  );

revoke all on public.mission_items from anon;
revoke insert, update, delete on public.mission_items from authenticated;
grant select on public.mission_items to authenticated;

-- Paiements de mission (déjà utilisée par l'application ; créée seulement si absente).
create table if not exists public.mission_payments (
  id           uuid primary key default gen_random_uuid(),
  mission_id   uuid not null references public.missions (id) on delete cascade,
  kind         text not null check (kind in ('trajet', 'reparation')),
  amount_fcfa  integer not null check (amount_fcfa > 0),
  operateur    text not null,
  payer_phone  text,
  reference    text,
  confirmed_at timestamptz,
  rejected_at  timestamptz,
  reject_reason text,
  created_at   timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 3. Commande : create_mission liée au catalogue (remplace l'ancienne)
-- -----------------------------------------------------------------------------
drop function if exists public.create_mission(
  uuid, text, text, text, double precision, double precision, text);

create or replace function public.create_mission(
  p_provider    uuid,
  p_vehicle     text,
  p_items       uuid[],
  p_lat         double precision,
  p_lng         double precision,
  p_description text default null,
  p_address     text default null
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid     uuid := auth.uid();
  v_pv      public.providers%rowtype;
  v_ids     uuid[];
  v_found   integer;
  v_repair  integer;
  v_problem text;
  v_km      numeric;
  v_fee     integer;
  v_id      uuid;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if exists (select 1 from public.profiles where id = v_uid and is_suspended) then
    raise exception 'COMPTE_SUSPENDU' using errcode = 'P0001';
  end if;
  if p_provider is null or p_provider = v_uid then
    raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002';
  end if;
  if p_vehicle is null or p_vehicle not in ('moto', 'voiture', 'camion') then
    raise exception 'VEHICULE_INVALIDE' using errcode = '22023';
  end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'POSITION_INCONNUE' using errcode = 'P0001';
  end if;

  select coalesce(array_agg(distinct x), '{}') into v_ids from unnest(p_items) as x;
  if cardinality(v_ids) = 0 or cardinality(v_ids) > 8 then
    raise exception 'PRESTATIONS_OBLIGATOIRES' using errcode = '22023';
  end if;

  select pv.* into v_pv
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.id = p_provider
     and pv.statut_validation = 'approved'
     and pv.fin_abonnement > now()
     and not pf.is_suspended;
  if not found then
    raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002';
  end if;
  if not v_pv.disponible
     or exists (select 1 from public.wallets w where w.provider_id = p_provider and w.blocked) then
    raise exception 'PRESTATAIRE_INDISPONIBLE' using errcode = 'P0001';
  end if;
  if not (p_vehicle = any (v_pv.vehicle_types)) then
    raise exception 'VEHICULE_NON_PRIS_EN_CHARGE' using errcode = 'P0001';
  end if;
  -- Le déplacement se paie avant l'envoi, en Mobile Money : le prestataire doit
  -- avoir renseigné son compte de réception.
  if v_pv.momo_numero is null or v_pv.momo_operateur is null then
    raise exception 'PAIEMENT_MOBILE_INDISPONIBLE' using errcode = 'P0001';
  end if;

  if (select count(*) from public.missions
       where client_id = v_uid
         and status in ('pending', 'accepted', 'arrived', 'working')) >= 3 then
    raise exception 'TROP_DE_DEMANDES' using errcode = 'P0001';
  end if;

  -- Les prestations doivent appartenir à CE prestataire et à CE type de véhicule.
  select count(*), coalesce(sum(i.prix_fcfa), 0)
    into v_found, v_repair
    from public.provider_catalog_items i
   where i.id = any (v_ids)
     and i.provider_id = p_provider
     and i.categorie_vehicule = p_vehicle;
  if v_found <> cardinality(v_ids) then
    raise exception 'PRESTATION_INTROUVABLE' using errcode = 'P0002';
  end if;

  v_km := round((public.haversine_km(p_lat, p_lng, v_pv.latitude, v_pv.longitude) * 1.25)::numeric, 2);
  if v_pv.rayon_max_km is not null and v_km > v_pv.rayon_max_km then
    raise exception 'HORS_RAYON' using errcode = 'P0001';
  end if;
  -- Même règle que l'estimation affichée au client (TravelFee.estimate).
  v_fee := greatest(
             (ceil(v_km * coalesce(v_pv.tarif_km_fcfa, 0) / 50.0))::integer * 50,
             coalesce(v_pv.frais_deplacement_min_fcfa, 0));

  select left(string_agg(i.nom, ' + ' order by i.created_at, i.id), 300)
    into v_problem
    from public.provider_catalog_items i where i.id = any (v_ids);
  if char_length(v_problem) < 3 then
    v_problem := 'Prestation ' || v_problem;
  end if;

  insert into public.missions
    (client_id, provider_id, vehicle_type, problem, description, client_lat, client_lng,
     client_address, distance_km, travel_fee_fcfa, repair_fee_fcfa, travel_fee_paid, status)
  values
    (v_uid, p_provider, p_vehicle, v_problem,
     left(nullif(btrim(p_description), ''), 500),
     p_lat, p_lng, left(nullif(btrim(p_address), ''), 300),
     v_km, v_fee, v_repair, false, 'pending')
  returning id into v_id;

  -- Prix figés : une modification ultérieure du catalogue ne change pas la commande.
  insert into public.mission_items (mission_id, catalog_item_id, nom, prix_fcfa)
  select v_id, i.id, i.nom, i.prix_fcfa
    from public.provider_catalog_items i where i.id = any (v_ids);

  perform public.log_mission_event(v_id, 'created',
    jsonb_build_object('items', cardinality(v_ids), 'distance_km', v_km,
                       'travel_fee_fcfa', v_fee, 'repair_fee_fcfa', v_repair));
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Actions du prestataire : plus de prix libre, déplacement payé avant accord
-- -----------------------------------------------------------------------------
drop function if exists public.mission_provider_action(uuid, text, integer);
drop function if exists public.mission_provider_action(uuid, text);

create or replace function public.mission_provider_action(
  p_mission uuid,
  p_action  text
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  m      public.missions%rowtype;
  v_dist double precision;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  select * into m from public.missions
   where id = p_mission and provider_id = v_uid
   for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  if p_action = 'accept' then
    if m.status <> 'pending' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if not exists (
      select 1 from public.providers pv
       where pv.id = v_uid and pv.statut_validation = 'approved'
    ) then
      raise exception 'PRESTATAIRE_NON_VALIDE' using errcode = 'P0001';
    end if;
    -- Garantie de déplacement : le client a déjà payé en Mobile Money.
    if m.travel_fee_fcfa > 0 and not exists (
      select 1 from public.mission_payments pay
       where pay.mission_id = m.id
         and pay.kind = 'trajet'
         and pay.operateur <> 'especes'
         and pay.rejected_at is null
    ) then
      raise exception 'FRAIS_NON_PAYES' using errcode = 'P0001';
    end if;

    -- Accepter = reconnaître avoir reçu le SMS Mobile Money du déplacement.
    update public.mission_payments
       set confirmed_at = now()
     where mission_id = m.id and kind = 'trajet'
       and confirmed_at is null and rejected_at is null;

    update public.missions set status = 'accepted', accepted_at = now() where id = m.id;
    update public.providers set statut_mission = 'accepted' where id = v_uid;
    perform public.log_mission_event(m.id, 'accepted');
    perform public.safe_notify(m.client_id, 'mission_accepted', 'Dépanneur en route',
      'Votre demande a été acceptée. Suivez son arrivée en direct.',
      jsonb_build_object('mission_id', m.id));

  elsif p_action = 'refuse' then
    if m.status <> 'pending' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    update public.missions set status = 'refused' where id = m.id;
    update public.providers set statut_mission = 'refused' where id = v_uid;
    perform public.log_mission_event(m.id, 'refused');
    perform public.safe_notify(m.client_id, 'mission_refused', 'Demande refusée',
      'Ce dépanneur ne peut pas intervenir. Choisissez-en un autre sur la carte.',
      jsonb_build_object('mission_id', m.id));
    -- Déplacement déjà payé : l'administration doit rembourser le client.
    if exists (select 1 from public.mission_payments pay
                where pay.mission_id = m.id and pay.kind = 'trajet'
                  and pay.rejected_at is null) then
      perform public.log_mission_event(m.id, 'refund_due',
        jsonb_build_object('amount', m.travel_fee_fcfa));
      perform public.notify_admins('refund_due', 'Remboursement à effectuer',
        'Demande refusée après paiement du déplacement (' || m.travel_fee_fcfa || ' FCFA).',
        jsonb_build_object('mission_id', m.id));
    end if;

  elsif p_action = 'arrived' then
    if m.status <> 'accepted' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if m.provider_lat is null or m.provider_lng is null
       or m.provider_pos_at is null or m.provider_pos_at < now() - interval '5 minutes' then
      raise exception 'POSITION_INCONNUE' using errcode = 'P0001';
    end if;
    v_dist := public.haversine_km(m.provider_lat, m.provider_lng, m.client_lat, m.client_lng) * 1000;
    if v_dist > 500 then
      raise exception 'TROP_LOIN' using errcode = 'P0001';
    end if;
    update public.missions set status = 'arrived', arrived_at = now() where id = m.id;
    perform public.log_mission_event(m.id, 'arrived');
    perform public.safe_notify(m.client_id, 'mission_arrived', 'Dépanneur arrivé',
      'Votre dépanneur est sur place.', jsonb_build_object('mission_id', m.id));

  elsif p_action = 'start_work' then
    if m.status <> 'arrived' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    update public.missions set status = 'working', work_started_at = now() where id = m.id;
    perform public.log_mission_event(m.id, 'work_started');
    perform public.safe_notify(m.client_id, 'mission_working', 'Réparation commencée',
      'Le dépanneur a commencé le travail.', jsonb_build_object('mission_id', m.id));

  elsif p_action = 'end_work' then
    if m.status <> 'working' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    -- Le prix de la réparation est celui des prestations commandées : aucune saisie.
    update public.missions
       set status = 'completed', work_ended_at = now()
     where id = m.id;
    update public.providers
       set missions_completees = missions_completees + 1, statut_mission = 'completed'
     where id = v_uid;
    perform public.log_mission_event(m.id, 'work_ended',
      jsonb_build_object('repair_fee_fcfa', m.repair_fee_fcfa));
    perform public.safe_notify(m.client_id, 'mission_completed', 'Réparation terminée',
      'Consultez le montant et réglez votre dépanneur.',
      jsonb_build_object('mission_id', m.id));

  else
    raise exception 'ACTION_INVALIDE' using errcode = '22023';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. Envoi au prestataire dès que le déplacement est payé
-- -----------------------------------------------------------------------------
create or replace function public.notify_provider_trajet_paid()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_provider uuid;
  v_problem  text;
begin
  if new.kind <> 'trajet' or new.operateur = 'especes' then
    return new;
  end if;
  select m.provider_id, m.problem into v_provider, v_problem
    from public.missions m where m.id = new.mission_id;
  if v_provider is not null then
    perform public.safe_notify(v_provider, 'mission_paid_request',
      'Nouvelle demande payée',
      'Déplacement réglé (' || new.amount_fcfa || ' FCFA) : ' || coalesce(v_problem, 'demande de dépannage'),
      jsonb_build_object('mission_id', new.mission_id));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_mission_payments_notify on public.mission_payments;
create trigger trg_mission_payments_notify
  after insert on public.mission_payments
  for each row execute function public.notify_provider_trajet_paid();


-- -----------------------------------------------------------------------------
-- 5b. Déclaration de paiement : le montant vient TOUJOURS du serveur
--     (déplacement payé dès la commande, réparation après la fin du travail).
-- -----------------------------------------------------------------------------
drop function if exists public.declare_mission_payment(uuid, text, text, text, text);

create or replace function public.declare_mission_payment(
  p_mission   uuid,
  p_kind      text,
  p_operateur text,
  p_phone     text default null,
  p_ref       text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  m        public.missions%rowtype;
  v_amount integer;
  v_phone  text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  v_ref    text := upper(btrim(coalesce(p_ref, '')));
  v_op_pro text;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  select * into m from public.missions where id = p_mission and client_id = v_uid for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  if p_kind not in ('trajet', 'reparation') then
    raise exception 'RIEN_A_PAYER' using errcode = '22023';
  end if;
  if p_operateur not in ('mtn', 'moov', 'celtiis', 'especes') then
    raise exception 'OPERATEUR_INVALIDE' using errcode = '22023';
  end if;

  if p_kind = 'trajet' then
    -- Le déplacement se règle avant l'envoi : Mobile Money uniquement.
    if m.status <> 'pending' or p_operateur = 'especes' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    v_amount := m.travel_fee_fcfa;
  else
    if m.status not in ('completed', 'working') then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    v_amount := m.repair_fee_fcfa;
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'RIEN_A_PAYER' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.mission_payments
              where mission_id = m.id and kind = p_kind and rejected_at is null) then
    raise exception 'DEJA_DECLARE' using errcode = 'P0001';
  end if;

  if p_operateur <> 'especes' then
    select momo_operateur into v_op_pro from public.providers where id = m.provider_id;
    if v_op_pro is null then
      raise exception 'OPERATEUR_INVALIDE' using errcode = 'P0001';
    end if;
    if char_length(v_phone) < 8 then
      raise exception 'TELEPHONE_INVALIDE' using errcode = '22023';
    end if;
    if char_length(v_ref) < 4 then
      raise exception 'REFERENCE_INVALIDE' using errcode = '22023';
    end if;
    if exists (select 1 from public.mission_payments
                where upper(reference) = v_ref and rejected_at is null) then
      raise exception 'REFERENCE_DEJA_UTILISEE' using errcode = 'P0001';
    end if;
  end if;

  insert into public.mission_payments
    (mission_id, kind, amount_fcfa, operateur, payer_phone, reference)
  values
    (m.id, p_kind, v_amount, p_operateur, nullif(v_phone, ''), nullif(v_ref, ''));

  perform public.log_mission_event(m.id, 'payment_declared',
    jsonb_build_object('kind', p_kind, 'amount', v_amount, 'operateur', p_operateur));
end;
$$;

revoke all on function public.declare_mission_payment(uuid, text, text, text, text) from public, anon;
grant execute on function public.declare_mission_payment(uuid, text, text, text, text) to authenticated;

-- Annule les demandes dont le déplacement n'a pas été payé à temps.
-- À planifier (pg_cron) : select cron.schedule('expire-unpaid', '*/5 * * * *',
--                          $$select public.expire_unpaid_missions(20)$$);
create or replace function public.expire_unpaid_missions(p_minutes integer default 20)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_n integer;
begin
  with x as (
    update public.missions m
       set status = 'cancelled', cancelled_at = now(),
           cancel_reason = 'Frais de déplacement non payés à temps'
     where m.status = 'pending'
       and m.travel_fee_fcfa > 0
       and m.created_at < now() - make_interval(mins => greatest(p_minutes, 1))
       and not exists (select 1 from public.mission_payments pay
                        where pay.mission_id = m.id and pay.kind = 'trajet'
                          and pay.rejected_at is null)
    returning 1)
  select count(*) into v_n from x;
  return v_n;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Droits d'exécution
-- -----------------------------------------------------------------------------
revoke all on function public.create_mission(
  uuid, text, uuid[], double precision, double precision, text, text) from public, anon;
grant execute on function public.create_mission(
  uuid, text, uuid[], double precision, double precision, text, text) to authenticated;

revoke all on function public.mission_provider_action(uuid, text) from public, anon;
grant execute on function public.mission_provider_action(uuid, text) to authenticated;

revoke all on function public.set_provider_catalog(
  text[], jsonb, integer, integer, integer, text) from public, anon;
grant execute on function public.set_provider_catalog(
  text[], jsonb, integer, integer, integer, text) to authenticated;

revoke all on function public.provider_public_catalog(uuid) from public;
grant execute on function public.provider_public_catalog(uuid) to anon, authenticated;

revoke all on function public.notify_provider_trajet_paid() from public, anon, authenticated;
revoke all on function public.expire_unpaid_missions(integer) from public, anon, authenticated;

-- Ancienne fonction de paiement libre (supprimée au script 08, recréée si 05/06 sont rejoués).
drop function if exists public.pay_mission_travel_fee(uuid);

commit;
