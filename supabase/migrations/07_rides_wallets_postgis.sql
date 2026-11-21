-- =============================================================================
-- MONTOTEM : Script 07 - PostGIS, wallets, courses (rides), rôles admin, RLS
-- Fichier  : sql/07_rides_wallets_postgis.sql
-- Idempotent : peut être rejoué sans erreur.
-- =============================================================================
BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;
SET LOCAL search_path TO public, extensions;

-- -----------------------------------------------------------------------------
-- 1. Configuration plateforme (commission, seuil de blocage)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_config (
  key        TEXT PRIMARY KEY,
  value_int  INTEGER,
  note       TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.app_config (key, value_int, note) VALUES
  ('commission_cash_pct',          15,    'Commission (%) prélevée sur les courses payées en cash'),
  ('wallet_block_threshold_fcfa',  -2000, 'Le prestataire est bloqué si son solde passe sous ce seuil (FCFA)')
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. Fonctions utilitaires
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Profils : colonnes complémentaires (table créée par les scripts 01/05)
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS country_code TEXT NOT NULL DEFAULT 'BJ',
  ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT FALSE;

-- -----------------------------------------------------------------------------
-- 4. Rôles administrateur
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_roles (
  user_id    UUID PRIMARY KEY REFERENCES public.profiles (id) ON DELETE CASCADE,
  level      TEXT NOT NULL DEFAULT 'support'
             CHECK (level IN ('super_admin', 'finance', 'support', 'moderator')),
  granted_by UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- is_admin() : profil role = 'admin' OU présent dans admin_roles.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
           SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid() AND p.role = 'admin'
         )
      OR EXISTS (
           SELECT 1 FROM public.admin_roles a
            WHERE a.user_id = auth.uid()
         );
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_roles a
     WHERE a.user_id = auth.uid() AND a.level = 'super_admin'
  );
$$;

-- -----------------------------------------------------------------------------
-- 5. Prestataires : type de service + position géographique PostGIS
-- -----------------------------------------------------------------------------
ALTER TABLE public.providers
  ADD COLUMN IF NOT EXISTS provider_kind TEXT,
  ADD COLUMN IF NOT EXISTS location GEOGRAPHY(Point, 4326);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'providers_provider_kind_check'
  ) THEN
    ALTER TABLE public.providers
      ADD CONSTRAINT providers_provider_kind_check
      CHECK (provider_kind IS NULL OR provider_kind IN (
        'zemidjan', 'tricycle_fret', 'vulcanisateur', 'mecanicien',
        'electricien', 'station', 'garage'
      ));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.providers_sync_location()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
    NEW.location := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_providers_sync_location ON public.providers;
CREATE TRIGGER trg_providers_sync_location
  BEFORE INSERT OR UPDATE OF latitude, longitude ON public.providers
  FOR EACH ROW EXECUTE FUNCTION public.providers_sync_location();

-- Rattrapage des prestataires existants.
UPDATE public.providers
   SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
 WHERE location IS NULL
   AND latitude IS NOT NULL AND longitude IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_providers_location ON public.providers USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_providers_kind     ON public.providers (provider_kind);

-- -----------------------------------------------------------------------------
-- 6. Wallets prestataires + grand livre
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallets (
  provider_id UUID PRIMARY KEY REFERENCES public.providers (id) ON DELETE CASCADE,
  balance_fcfa INTEGER NOT NULL DEFAULT 0,
  blocked      BOOLEAN NOT NULL DEFAULT FALSE,
  blocked_at   TIMESTAMPTZ,
  block_reason TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider_id   UUID NOT NULL REFERENCES public.wallets (provider_id) ON DELETE CASCADE,
  ride_id       UUID,
  kind          TEXT NOT NULL
                CHECK (kind IN ('commission_cash', 'topup', 'adjustment', 'refund')),
  amount_fcfa   INTEGER NOT NULL CHECK (amount_fcfa <> 0),
  balance_after INTEGER NOT NULL,
  reference     TEXT,
  note          TEXT,
  created_by    UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_provider ON public.wallet_transactions (provider_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_wallet_tx_reference
  ON public.wallet_transactions (reference) WHERE reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_wallet_tx_ride_commission
  ON public.wallet_transactions (ride_id) WHERE kind = 'commission_cash';

-- Création automatique du wallet à l'inscription d'un prestataire.
CREATE OR REPLACE FUNCTION public.providers_create_wallet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  INSERT INTO public.wallets (provider_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_providers_create_wallet ON public.providers;
CREATE TRIGGER trg_providers_create_wallet
  AFTER INSERT ON public.providers
  FOR EACH ROW EXECUTE FUNCTION public.providers_create_wallet();

-- Rattrapage des prestataires existants.
INSERT INTO public.wallets (provider_id)
SELECT id FROM public.providers
ON CONFLICT DO NOTHING;

-- Blocage / déblocage automatique selon le solde.
CREATE OR REPLACE FUNCTION public.wallets_auto_block()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_threshold INTEGER;
BEGIN
  SELECT value_int INTO v_threshold
    FROM public.app_config WHERE key = 'wallet_block_threshold_fcfa';
  v_threshold := COALESCE(v_threshold, -2000);

  NEW.updated_at := NOW();

  IF NEW.balance_fcfa < v_threshold THEN
    IF NOT NEW.blocked THEN
      NEW.blocked      := TRUE;
      NEW.blocked_at   := NOW();
      NEW.block_reason := 'WALLET_SOUS_SEUIL';
    END IF;
  ELSIF NEW.blocked AND NEW.block_reason = 'WALLET_SOUS_SEUIL' THEN
    NEW.blocked      := FALSE;
    NEW.blocked_at   := NULL;
    NEW.block_reason := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wallets_auto_block ON public.wallets;
CREATE TRIGGER trg_wallets_auto_block
  BEFORE INSERT OR UPDATE OF balance_fcfa ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.wallets_auto_block();

-- Effets de bord : hors ligne + notification quand l'état de blocage change.
CREATE OR REPLACE FUNCTION public.wallets_after_block_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.blocked AND NOT OLD.blocked THEN
    UPDATE public.providers SET disponible = FALSE WHERE id = NEW.provider_id;
    BEGIN
      PERFORM public.notify_user(
        NEW.provider_id, 'wallet_blocked', 'Compte bloqué',
        'Votre solde est inférieur au seuil autorisé. Rechargez votre wallet pour reprendre les courses.',
        jsonb_build_object('balance_fcfa', NEW.balance_fcfa)
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  ELSIF OLD.blocked AND NOT NEW.blocked THEN
    BEGIN
      PERFORM public.notify_user(
        NEW.provider_id, 'wallet_unblocked', 'Compte débloqué',
        'Votre wallet est de nouveau à jour. Vous pouvez reprendre les courses.',
        jsonb_build_object('balance_fcfa', NEW.balance_fcfa)
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wallets_after_block_change ON public.wallets;
CREATE TRIGGER trg_wallets_after_block_change
  AFTER UPDATE OF blocked ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.wallets_after_block_change();

-- -----------------------------------------------------------------------------
-- 7. Courses (Zémidjan, Tricycle Fret, ...)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rides (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id          UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  provider_id        UUID REFERENCES public.providers (id) ON DELETE SET NULL,
  service_kind       TEXT NOT NULL
                     CHECK (service_kind IN ('zemidjan', 'tricycle_fret')),
  status             TEXT NOT NULL DEFAULT 'requested'
                     CHECK (status IN ('requested', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled')),
  pickup             GEOGRAPHY(Point, 4326) NOT NULL,
  dropoff            GEOGRAPHY(Point, 4326) NOT NULL,
  pickup_address     TEXT,
  dropoff_address    TEXT,
  distance_m         INTEGER NOT NULL DEFAULT 0 CHECK (distance_m >= 0),
  fare_fcfa          INTEGER NOT NULL CHECK (fare_fcfa BETWEEN 100 AND 500000),
  final_fare_fcfa    INTEGER CHECK (final_fare_fcfa IS NULL OR final_fare_fcfa BETWEEN 100 AND 500000),
  payment_method     TEXT NOT NULL DEFAULT 'cash'
                     CHECK (payment_method IN ('cash', 'mtn', 'moov', 'celtiis')),
  commission_fcfa    INTEGER NOT NULL DEFAULT 0 CHECK (commission_fcfa >= 0),
  commission_applied BOOLEAN NOT NULL DEFAULT FALSE,
  cancel_reason      TEXT,
  cancelled_by       UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  accepted_at        TIMESTAMPTZ,
  arrived_at         TIMESTAMPTZ,
  started_at         TIMESTAMPTZ,
  completed_at       TIMESTAMPTZ,
  cancelled_at       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT rides_provider_not_client CHECK (provider_id IS NULL OR provider_id <> client_id)
);

CREATE INDEX IF NOT EXISTS idx_rides_client   ON public.rides (client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rides_provider ON public.rides (provider_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rides_open     ON public.rides (service_kind, created_at DESC) WHERE status = 'requested';
CREATE INDEX IF NOT EXISTS idx_rides_pickup   ON public.rides USING GIST (pickup);

DROP TRIGGER IF EXISTS trg_rides_updated_at ON public.rides;
CREATE TRIGGER trg_rides_updated_at
  BEFORE UPDATE ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Commission cash : déduite du wallet à la clôture de la course.
CREATE OR REPLACE FUNCTION public.rides_apply_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_pct  INTEGER;
  v_base INTEGER;
  v_comm INTEGER;
  v_bal  INTEGER;
BEGIN
  NEW.completed_at    := COALESCE(NEW.completed_at, NOW());
  NEW.final_fare_fcfa := COALESCE(NEW.final_fare_fcfa, NEW.fare_fcfa);
  v_base := NEW.final_fare_fcfa;

  IF NEW.payment_method <> 'cash'
     OR NEW.commission_applied
     OR NEW.provider_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT value_int INTO v_pct
    FROM public.app_config WHERE key = 'commission_cash_pct';
  v_pct  := COALESCE(v_pct, 15);
  v_comm := ROUND(v_base * v_pct / 100.0)::integer;

  IF v_comm > 0 THEN
    INSERT INTO public.wallets (provider_id) VALUES (NEW.provider_id)
      ON CONFLICT DO NOTHING;

    UPDATE public.wallets
       SET balance_fcfa = balance_fcfa - v_comm
     WHERE provider_id = NEW.provider_id
    RETURNING balance_fcfa INTO v_bal;

    INSERT INTO public.wallet_transactions
      (provider_id, ride_id, kind, amount_fcfa, balance_after, note)
    VALUES
      (NEW.provider_id, NEW.id, 'commission_cash', -v_comm, v_bal,
       'Commission ' || v_pct || ' % sur course cash de ' || v_base || ' FCFA');
  END IF;

  NEW.commission_fcfa    := v_comm;
  NEW.commission_applied := TRUE;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rides_apply_commission ON public.rides;
CREATE TRIGGER trg_rides_apply_commission
  BEFORE UPDATE OF status ON public.rides
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  EXECUTE FUNCTION public.rides_apply_commission();

-- Garde : un prestataire bloqué ne peut pas accepter (rides).
CREATE OR REPLACE FUNCTION public.guard_blocked_provider()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.status = 'accepted' AND OLD.status = 'requested' AND NEW.provider_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.wallets w
       WHERE w.provider_id = NEW.provider_id AND w.blocked
    ) THEN
      RAISE EXCEPTION 'WALLET_BLOQUE' USING errcode = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rides_guard_blocked ON public.rides;
CREATE TRIGGER trg_rides_guard_blocked
  BEFORE UPDATE OF status ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_provider();

-- Même garde sur les missions de dépannage existantes.
DO $$
BEGIN
  IF to_regclass('public.missions') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_missions_guard_blocked ON public.missions';
    EXECUTE 'CREATE TRIGGER trg_missions_guard_blocked
               BEFORE UPDATE OF status ON public.missions
               FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_provider()';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 8. RPC : courses
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_ride(
  p_service_kind    TEXT,
  p_pickup_lat      DOUBLE PRECISION,
  p_pickup_lng      DOUBLE PRECISION,
  p_dropoff_lat     DOUBLE PRECISION,
  p_dropoff_lng     DOUBLE PRECISION,
  p_fare_fcfa       INTEGER,
  p_payment_method  TEXT DEFAULT 'cash',
  p_pickup_address  TEXT DEFAULT NULL,
  p_dropoff_address TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_pickup GEOGRAPHY;
  v_drop   GEOGRAPHY;
  v_id     UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NON_CONNECTE' USING errcode = '28000';
  END IF;
  IF p_service_kind NOT IN ('zemidjan', 'tricycle_fret') THEN
    RAISE EXCEPTION 'SERVICE_INVALIDE' USING errcode = '22023';
  END IF;
  IF p_payment_method NOT IN ('cash', 'mtn', 'moov', 'celtiis') THEN
    RAISE EXCEPTION 'PAIEMENT_INVALIDE' USING errcode = '22023';
  END IF;
  IF p_fare_fcfa IS NULL OR p_fare_fcfa < 100 OR p_fare_fcfa > 500000 THEN
    RAISE EXCEPTION 'TARIF_INVALIDE' USING errcode = '22023';
  END IF;
  IF p_pickup_lat NOT BETWEEN -90 AND 90 OR p_dropoff_lat NOT BETWEEN -90 AND 90
     OR p_pickup_lng NOT BETWEEN -180 AND 180 OR p_dropoff_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'POSITION_INVALIDE' USING errcode = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.rides r
     WHERE r.client_id = v_uid AND r.status IN ('requested', 'accepted', 'arrived', 'in_progress')
  ) THEN
    RAISE EXCEPTION 'COURSE_EN_COURS' USING errcode = 'P0001';
  END IF;

  v_pickup := ST_SetSRID(ST_MakePoint(p_pickup_lng,  p_pickup_lat),  4326)::geography;
  v_drop   := ST_SetSRID(ST_MakePoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography;

  INSERT INTO public.rides
    (client_id, service_kind, pickup, dropoff, pickup_address, dropoff_address,
     distance_m, fare_fcfa, payment_method)
  VALUES
    (v_uid, p_service_kind, v_pickup, v_drop,
     LEFT(NULLIF(BTRIM(p_pickup_address), ''), 300),
     LEFT(NULLIF(BTRIM(p_dropoff_address), ''), 300),
     ROUND(ST_Distance(v_pickup, v_drop))::integer, p_fare_fcfa, p_payment_method)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Actions : accept | arrived | start | complete | cancel
CREATE OR REPLACE FUNCTION public.ride_action(
  p_ride   UUID,
  p_action TEXT,
  p_fare   INTEGER DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_r   public.rides%rowtype;
  v_pv  public.providers%rowtype;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NON_CONNECTE' USING errcode = '28000';
  END IF;

  SELECT * INTO v_r FROM public.rides WHERE id = p_ride FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INTROUVABLE' USING errcode = 'P0002';
  END IF;

  IF p_action = 'accept' THEN
    IF v_r.status <> 'requested' OR v_r.provider_id IS NOT NULL THEN
      RAISE EXCEPTION 'STATUT_INVALIDE' USING errcode = 'P0001';
    END IF;
    IF v_r.client_id = v_uid THEN
      RAISE EXCEPTION 'INTERDIT' USING errcode = '42501';
    END IF;

    SELECT * INTO v_pv FROM public.providers pv
     WHERE pv.id = v_uid
       AND pv.statut_validation = 'approved'
       AND pv.fin_abonnement > NOW();
    IF NOT FOUND THEN
      RAISE EXCEPTION 'PRESTATAIRE_NON_ACTIF' USING errcode = 'P0001';
    END IF;
    IF v_pv.provider_kind IS DISTINCT FROM v_r.service_kind THEN
      RAISE EXCEPTION 'SERVICE_INCOMPATIBLE' USING errcode = 'P0001';
    END IF;

    UPDATE public.rides
       SET provider_id = v_uid, status = 'accepted', accepted_at = NOW()
     WHERE id = v_r.id;
    RETURN 'accepted';

  ELSIF p_action IN ('arrived', 'start', 'complete') THEN
    IF v_r.provider_id IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'INTERDIT' USING errcode = '42501';
    END IF;

    IF p_action = 'arrived' THEN
      IF v_r.status <> 'accepted' THEN
        RAISE EXCEPTION 'STATUT_INVALIDE' USING errcode = 'P0001';
      END IF;
      UPDATE public.rides SET status = 'arrived', arrived_at = NOW() WHERE id = v_r.id;
      RETURN 'arrived';

    ELSIF p_action = 'start' THEN
      IF v_r.status <> 'arrived' THEN
        RAISE EXCEPTION 'STATUT_INVALIDE' USING errcode = 'P0001';
      END IF;
      UPDATE public.rides SET status = 'in_progress', started_at = NOW() WHERE id = v_r.id;
      RETURN 'in_progress';

    ELSE
      IF v_r.status <> 'in_progress' THEN
        RAISE EXCEPTION 'STATUT_INVALIDE' USING errcode = 'P0001';
      END IF;
      IF p_fare IS NOT NULL AND (p_fare < 100 OR p_fare > 500000) THEN
        RAISE EXCEPTION 'TARIF_INVALIDE' USING errcode = '22023';
      END IF;
      UPDATE public.rides
         SET status = 'completed',
             final_fare_fcfa = COALESCE(p_fare, fare_fcfa)
       WHERE id = v_r.id;
      RETURN 'completed';
    END IF;

  ELSIF p_action = 'cancel' THEN
    IF v_uid NOT IN (v_r.client_id, COALESCE(v_r.provider_id, v_r.client_id)) THEN
      RAISE EXCEPTION 'INTERDIT' USING errcode = '42501';
    END IF;
    IF v_r.status IN ('completed', 'cancelled', 'in_progress') THEN
      RAISE EXCEPTION 'STATUT_INVALIDE' USING errcode = 'P0001';
    END IF;
    UPDATE public.rides
       SET status = 'cancelled', cancelled_at = NOW(), cancelled_by = v_uid,
           cancel_reason = LEFT(NULLIF(BTRIM(p_reason), ''), 300)
     WHERE id = v_r.id;
    RETURN 'cancelled';
  END IF;

  RAISE EXCEPTION 'ACTION_INVALIDE' USING errcode = '22023';
END;
$$;

-- Courses ouvertes autour du prestataire connecté (vide si wallet bloqué).
CREATE OR REPLACE FUNCTION public.rides_nearby(
  p_lat        DOUBLE PRECISION,
  p_lng        DOUBLE PRECISION,
  p_radius_km NUMERIC DEFAULT 5
) RETURNS TABLE (
  id                     UUID,
  service_kind         TEXT,
  pickup_address       TEXT,
  dropoff_address      TEXT,
  fare_fcfa            INTEGER,
  payment_method       TEXT,
  distance_to_pickup_m INTEGER,
  trip_distance_m      INTEGER,
  created_at           TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_provider_blocked BOOLEAN;
  v_user_location GEOGRAPHY;
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT blocked INTO v_provider_blocked
      FROM public.wallets
     WHERE provider_id = v_uid;

    IF COALESCE(v_provider_blocked, FALSE) THEN
      RETURN;
    END IF;
  END IF;

  v_user_location := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  RETURN QUERY
  SELECT 
    r.id,
    r.service_kind,
    r.pickup_address,
    r.dropoff_address,
    r.fare_fcfa,
    r.payment_method,
    ROUND(ST_Distance(r.pickup, v_user_location))::integer AS distance_to_pickup_m,
    r.distance_m AS trip_distance_m,
    r.created_at
  FROM public.rides r
  WHERE r.status = 'requested'
    AND ST_DWithin(r.pickup, v_user_location, p_radius_km * 1000)
  ORDER BY distance_to_pickup_m ASC;
END;
$$;

COMMIT;