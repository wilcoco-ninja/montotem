import 'package:montotem/core/flavor/app_flavor.dart';
import 'package:montotem/main.dart';

/// Console d'administration MonTotem (web).
///
/// La console s'ouvre directement sur la porte admin : /admin/login.
/// Seuls les comptes `admin` et `super_admin` peuvent y entrer (contrôlé
/// côté serveur par `is_admin`).
///
/// Lancement :  flutter run -d chrome -t lib/main_admin.dart
Future<void> main() => bootstrap(AppFlavor.admin);
