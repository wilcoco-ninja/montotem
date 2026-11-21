-- =============================================================================
-- MONTOTEM : Configuration des numéros de réception Mobile Money (MTN / Moov)
-- =============================================================================

insert into public.payment_settings (operateur, numero, titulaire) 
values 
  ('mtn',  '+2290167182343', 'MONTOTEM BENIN'),
  ('moov', '+229010000000', 'MONTOTEM BENIN')
on conflict (operateur) do update 
set numero = excluded.numero, 
    titulaire = excluded.titulaire;