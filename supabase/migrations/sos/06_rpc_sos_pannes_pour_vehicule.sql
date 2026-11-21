-- ============================================================================
-- MonTotem — SOS PANNE : Script 06/10
-- RPC sos_pannes_pour_vehicule : liste des pannes compatibles avec un
-- véhicule (filtrage dynamique strict de l'Étape 3).
--
-- Exécution : après les scripts 01-05. Non destructif, idempotent.
-- Prérequis : 03 (matrice panne ↔ véhicule).
-- ============================================================================

begin;

create or replace function sos_pannes_pour_vehicule(p_vehicule text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $func$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'code',              p.code,
        'libelle',           p.libelle,
        'description',       p.description,
        'main_oeuvre_fcfa',  p.main_oeuvre_fcfa,
        'piece_obligatoire', p.piece_obligatoire,
        'piece_code',        p.piece_code,
        'piece_libelle',     p.piece_libelle
      ) order by p.position
    ) filter (where p.code is not null),
    '[]'::jsonb)
  from sos_pannes p
  join sos_panne_vehicules pv on pv.panne_code = p.code
  where pv.vehicule_code = upper(btrim(p_vehicule));
$func$;

revoke all on function sos_pannes_pour_vehicule(text) from public;
grant execute on function sos_pannes_pour_vehicule(text) to anon, authenticated;

commit;