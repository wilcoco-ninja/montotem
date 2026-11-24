import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/provider_kind_choice_screen.dart';
import '../../features/emergency/presentation/survival_kit_screen.dart';
import '../../features/onboarding/presentation/provider_onboarding_screen.dart';
import '../../features/transport/presentation/transport_register_screen.dart';

/// Routes ajoutées par la refonte « Totem ». À insérer dans `AppRouter`
/// avec une seule ligne : `...totemRoutes,` (voir les 3 retouches du
/// routeur dans le message de livraison).
///
///  - /register/provider            → choix : Je conduis / Je dépanne
///  - /register/provider/depannage  → inscription dépanneur (existante)
///  - /register/transport           → inscription Zémidjan / Kloboto
///  - /survie                       → kit de survie (public, hors ligne)
final List<RouteBase> totemRoutes = [
  GoRoute(
    path: '/register/provider',
    builder: (_, __) => const ProviderKindChoiceScreen(),
  ),
  GoRoute(
    path: '/register/provider/depannage',
    builder: (_, __) => const ProviderOnboardingScreen(),
  ),
  GoRoute(
    path: '/register/transport',
    builder: (_, __) => const TransportRegisterScreen(),
  ),
  GoRoute(path: '/survie', builder: (_, __) => const SurvivalKitScreen()),
];
