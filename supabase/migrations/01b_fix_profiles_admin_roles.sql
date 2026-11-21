-- =============================================================================
-- MONTOTEM : Script 01b corrigé - Création, Alignement et Droits Administrateur
-- =============================================================================
BEGIN;

-- 1. Création de la table profiles si elle n'existe pas, puis ajout des colonnes
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  role TEXT NOT NULL DEFAULT 'client',
  first_name TEXT,
  last_name TEXT,
  phone TEXT,
  photo_profil_url TEXT,
  inscription_complete BOOLEAN NOT NULL DEFAULT FALSE,
  star_points INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'client',
  ADD COLUMN IF NOT EXISTS first_name TEXT,
  ADD COLUMN IF NOT EXISTS last_name TEXT,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS photo_profil_url TEXT,
  ADD COLUMN IF NOT EXISTS inscription_complete BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS star_points INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_role_check') THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_role_check CHECK (role IN ('client', 'provider', 'admin'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_star_points_check') THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_star_points_check CHECK (star_points >= 0);
  END IF;
END $$;

-- 2. Création de la table admin_roles si elle n'existe pas, puis ajout des colonnes
CREATE TABLE IF NOT EXISTS public.admin_roles (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  level TEXT NOT NULL,
  granted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.admin_roles
  ADD COLUMN IF NOT EXISTS granted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admin_roles_level_check') THEN
    ALTER TABLE public.admin_roles
      ADD CONSTRAINT admin_roles_level_check
      CHECK (level IN ('super_admin', 'finance', 'support', 'moderator'));
  END IF;
END $$;

-- 3. Fonctions is_admin() et is_super_admin()
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
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
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_roles a
     WHERE a.user_id = auth.uid() AND a.level = 'super_admin'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

-- 4. Insertion/Mise à jour sécurisée du profil utilisateur et de son rôle admin
INSERT INTO public.profiles (id, role, inscription_complete, updated_at)
VALUES ('137fe33a-7a3d-4680-9e67-f25b403fa5ba', 'admin', true, NOW())
ON CONFLICT (id) DO UPDATE 
SET role = 'admin',
    inscription_complete = true,
    updated_at = NOW();

INSERT INTO public.admin_roles (user_id, level)
VALUES ('137fe33a-7a3d-4680-9e67-f25b403fa5ba', 'super_admin')
ON CONFLICT (user_id) DO UPDATE 
SET level = 'super_admin';

COMMIT;