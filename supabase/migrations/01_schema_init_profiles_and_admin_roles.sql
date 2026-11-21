-- 1. Créer la table profiles si elle n'existe pas
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Créer la table admin_roles si elle n'existe pas
CREATE TABLE IF NOT EXISTS public.admin_roles (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  level TEXT NOT NULL
);

-- 3. Insérer le profil de l'utilisateur
INSERT INTO public.profiles (id, email)
VALUES ('137fe33a-7a3d-4680-9e67-f25b403fa5ba', 'wadam982@gmail.com')
ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

-- 4. Attribuer le rôle admin
INSERT INTO public.admin_roles (user_id, level)
VALUES ('137fe33a-7a3d-4680-9e67-f25b403fa5ba', 'super_admin')
ON CONFLICT (user_id) DO UPDATE SET level = 'super_admin';