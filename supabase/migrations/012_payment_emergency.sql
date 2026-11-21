-- =============================================================================
-- 012 — Numéros MoMo plateforme + numéros d'urgence
-- Dart : payment_account_service.dart (payment_settings),
--        emergency_numbers_repository.dart (emergency_numbers)
-- Dépend de : 010
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Dart : PaymentAccount.fromJson (operateur, numero, titulaire)
create table if not exists public.payment_settings (
  operateur  text primary key check (operateur in ('mtn','moov','celtiis')),
  numero     text not null check (numero ~ '^\+[0-9]{8,15}$'),
  titulaire  text not null default 'MONTOTEM BENIN',
  actif      boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.payment_settings (operateur, numero, titulaire)
values ('mtn', '+2290167182343', 'MONTOTEM BENIN')
on conflict (operateur) do nothing;

-- Dart : CountryNumbers.fromJson (country_code, police, fire, ambulance,
--        general, min_lat, max_lat, min_lng, max_lng, confidence)
create table if not exists public.emergency_numbers (
  country_code text primary key check (length(country_code) = 2),
  country_name text not null,
  police       text not null,
  fire         text not null,
  ambulance    text not null,
  general      text,
  confidence   text not null default 'a_confirmer'
               check (confidence in ('officiel','recoupe','a_confirmer')),
  min_lat double precision, max_lat double precision,
  min_lng double precision, max_lng double precision,
  source       text,
  verified_at  date,
  updated_at   timestamptz not null default now()
);

insert into public.emergency_numbers
  (country_code, country_name, police, fire, ambulance, general,
   confidence, min_lat, max_lat, min_lng, max_lng)
values
  ('BJ','Bénin','117','118','112','112','officiel', 6.04,12.34,0.67,3.90),
  ('TG','Togo','117','118','8200','112','officiel', 6.09,11.14,-0.16,1.80),
  ('NG','Nigeria','112','112','112','112','officiel', 4.27,13.89,2.67,14.68),
  ('BF','Burkina Faso','17','18','112','112','recoupe', 9.39,15.09,-5.52,2.41),
  ('NE','Niger','17','18','15','112','recoupe', 11.69,23.52,0.16,16.00),
  ('CI','Côte d''Ivoire','170','180','185','112','recoupe', 4.36,10.74,-8.60,-2.49),
  ('GH','Ghana','112','112','112','112','officiel', 4.74,11.17,-3.26,1.20),
  ('SN','Sénégal','17','18','15','112','officiel', 12.31,16.69,-17.53,-11.36),
  ('ML','Mali','17','18','15','112','recoupe', 10.14,25.00,-12.24,4.26),
  ('CM','Cameroun','117','118','119','112','officiel', 1.65,13.08,8.49,16.19),
  ('TD','Tchad','17','18','2251-4242','112','recoupe', 7.44,23.45,13.47,24.00)
on conflict (country_code) do update
set country_name = excluded.country_name,
    police = excluded.police, fire = excluded.fire, ambulance = excluded.ambulance,
    general = excluded.general, confidence = excluded.confidence,
    min_lat = excluded.min_lat, max_lat = excluded.max_lat,
    min_lng = excluded.min_lng, max_lng = excluded.max_lng,
    updated_at = now();

-- Dart : EmergencyNumbersRepository.synchroniser appelle rpc('get_emergency_numbers')
create or replace function public.get_emergency_numbers()
returns jsonb
language sql stable security definer set search_path = public, extensions
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'country_code', country_code, 'country_name', country_name,
    'police', police, 'fire', fire, 'ambulance', ambulance,
    'general', general, 'confidence', confidence,
    'min_lat', min_lat, 'max_lat', max_lat,
    'min_lng', min_lng, 'max_lng', max_lng
  ) order by country_name), '[]'::jsonb)
  from public.emergency_numbers;
$$;
grant execute on function public.get_emergency_numbers() to anon, authenticated;

commit;