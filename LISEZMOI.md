# MONTOTEM 14 — ordre d'installation
1. Supabase > SQL Editor : exécuter `14_catalog_priced_missions.sql` (une seule fois, en dernier).
2. Copier le dossier `lib/` du zip par-dessus `lib/` du projet (les chemins sont déjà `lib/features/...`).
   `provider_mission_screen.dart` est déjà corrigé dans le zip.
3. À la racine du projet : `dart run tool/apply_patches.dart`
   (corrige onboarding, fiche prestataire, suivi client, carte paiements, routeur ; crée des .bak ;
   ce qui ne s'applique pas est signalé, voir PATCHES.md pour le faire à la main).
4. `flutter analyze`.
5. Ajouter un bouton « Mes prestations et prix » → `context.push('/provider/catalog')` dans l'espace prestataire.
6. Supabase > pg_cron (optionnel) : annuler les demandes dont le déplacement n'est pas payé :
   `select cron.schedule('expire-unpaid','*/5 * * * *',$$select public.expire_unpaid_missions(20)$$);`
