import 'package:montotem/core/theme/app_space.dart';

/// Les 4 applications MonTotem — comme Uber / Uber Eats / Gozem / Back-office.
///
/// Chacune a sa propre icône sur le téléphone, son propre design,
/// sa propre porte d'entrée et son propre formulaire d'inscription.
///
///  - CLIENT     → MonTotem           · /login          · /register/quick
///  - DRIVER     → MonTotem Driver    · /driver/login   · /register/driver
///  - PRO        → MonTotem Pro       · /pro/login      · /register/provider
///  - ADMIN      → console web        · /admin/login    · (réservée admin)
///
/// Le rôle est fixé AVANT tout accès à `AppRouter.router` (voir main_*.dart).
enum AppFlavor {
  client('MonTotem', AppSpace.client, '/login', '/register/quick'),
  driver(
    'MonTotem Driver',
    AppSpace.driver,
    '/driver/login',
    '/register/driver',
  ),
  pro('MonTotem Pro', AppSpace.provider, '/pro/login', '/register/provider'),
  admin('MonTotem Admin', AppSpace.admin, '/admin/login', '/admin/login');

  const AppFlavor(this.appName, this.space, this.doorRoute, this.registerRoute);

  /// Nom affiché sur l'écran d'accueil du téléphone.
  final String appName;

  /// Espace visuel (thème) associé à cette app.
  final AppSpace space;

  /// Où envoyer un visiteur non connecté (porte d'authentification).
  final String doorRoute;

  /// Où envoyer un nouvel utilisateur qui veut s'inscrire.
  final String registerRoute;

  bool get isClient => this == AppFlavor.client;
  bool get isDriver => this == AppFlavor.driver;
  bool get isPro => this == AppFlavor.pro;
  bool get isAdmin => this == AppFlavor.admin;

  /// Racine d'accueil selon le rôle (après connexion).
  String get homeRoute => switch (this) {
    AppFlavor.client => '/home',
    AppFlavor.driver => '/driver/home',
    AppFlavor.pro => '/provider/home',
    AppFlavor.admin => '/admin/dashboard',
  };

  /// À définir UNE fois au démarrage, avant tout accès à `AppRouter.router`.
  static AppFlavor current = AppFlavor.client;
}
