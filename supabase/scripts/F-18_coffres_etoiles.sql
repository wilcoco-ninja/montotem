-- ═══════════════════════════════════════════════════════════════════════
-- F-18 · Coffres d'étoiles (dépense de points pour blagues/devinettes)
--
-- À exécuter UNE FOIS dans Supabase SQL Editor.
-- La fonction dépense N points d'étoiles du client connecté, inscrit
-- l'opération (delta négatif, reason 'coffre') dans star_points_ledger
-- et renvoie le nouveau solde. Tout est vérifié côté serveur :
-- impossible de dépenser plus que son solde.
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.depenser_etoiles(p_cout integer DEFAULT 15)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_solde     integer;
  v_new_solde integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NON_CONNECTE' USING ERRCODE = '28000';
  END IF;

  IF p_cout IS NULL OR p_cout < 1 OR p_cout > 100 THEN
    RAISE EXCEPTION 'COUT_INVALIDE' USING ERRCODE = '22023';
  END IF;

  SELECT star_points INTO v_solde
    FROM public.profiles
   WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFIL_INTROUVABLE' USING ERRCODE = 'P0001';
  END IF;

  IF v_solde < p_cout THEN
    RAISE EXCEPTION 'ETOILES_INSUFISANTES' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.profiles
     SET star_points = star_points - p_cout,
         updated_at  = now()
   WHERE id = v_uid
   RETURNING star_points INTO v_new_solde;

  INSERT INTO public.star_points_ledger (client_id, delta, reason)
  VALUES (v_uid, -p_cout, 'coffre');

  RETURN v_new_solde;
END;
$$;

-- Seuls les utilisateurs connectés peuvent dépenser leurs étoiles.
REVOKE EXECUTE ON FUNCTION public.depenser_etoiles(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.depenser_etoiles(integer) TO authenticated;

-- ─── Contrôles (à exécuter après le script) ───
-- SELECT proname FROM pg_proc
--  WHERE proname = 'depenser_etoiles';            -- 1 ligne attendue
-- SELECT client_id, delta, reason, created_at
--   FROM public.star_points_ledger ORDER BY created_at DESC LIMIT 3;
