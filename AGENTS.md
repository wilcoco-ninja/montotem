# Règles du projet MonTotem (Flutter / Supabase)

## Architecture
- Couches par feature : presentation → application → domain ← data.
- `domain/` : Dart pur. Aucun import de Flutter, Supabase, Dio, Provider, GoRouter.
- `.from('...')`, `.rpc('...')`, `.channel('...')` uniquement dans `features/*/data/datasources/`.
- Entre features, importer seulement le fichier d'API publique (`features/<x>/<x>.dart`).
- `core/` et `shared_kernel/` n'importent jamais `features/`, `apps/` ni `bootstrap/`.
- Les services (`features/services/*`) ne s'importent pas entre eux ; les autres features n'importent jamais `services/`.

## Interdits absolus
- Aucun secret, clé ou jeton dans le code, les fichiers de config suivis ou les logs.
- Ne jamais modifier une migration SQL déjà commitée : créer une nouvelle migration.
- Ne jamais écrire de logique de prix, de statut de commande, de solde ou de retrait dans l'app : uniquement des appels RPC.
- Aucun espace réservé (`// TODO`, `// ...`) : code complet uniquement.

## Argent et sécurité
- Toute fonction qui touche au wallet, aux paiements ou aux retraits : idempotente (`client_request_id`), atomique, avec tests.
- Toute nouvelle table : `country_code`, RLS activée, politiques testées.
- Ne jamais exécuter de commande contre l'environnement de production.

## Avant de terminer une tâche
1. `dart format lib test`
2. `flutter analyze` sans aucun problème
3. `flutter test` (inclut `test/architecture`)
4. Résumer les fichiers modifiés ; ne rien modifier hors du périmètre demandé.