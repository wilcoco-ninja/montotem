import 'package:flutter/material.dart';

import '../../../core/widgets/adaptive_scaffold.dart';
import 'provider_earnings_screen.dart';
import 'provider_home_screen.dart';
import 'provider_profile_screen.dart';

/// Coque de l'espace prestataire : Accueil · Gains · Profil.
///
/// Les écrans sont créés à la première visite. Gains et Profil sont
/// reconstruits à chaque ouverture pour afficher des chiffres à jour ;
/// l'Accueil (carte, GPS) reste en mémoire.
class ProviderShell extends StatefulWidget {
  const ProviderShell({super.key, this.initialTab = 0});

  /// 0 = Accueil, 1 = Gains, 2 = Profil.
  final int initialTab;

  @override
  State<ProviderShell> createState() => _ProviderShellState();
}

class _ProviderShellState extends State<ProviderShell> {
  late int _tab = widget.initialTab.clamp(0, 2).toInt();
  late final Set<int> _visites = {_tab};
  int _versionGains = 0;
  int _versionProfil = 0;

  void _aller(int i) {
    if (i == _tab) return;
    setState(() {
      if (i == 1) _versionGains++;
      if (i == 2) _versionProfil++;
      _visites.add(i);
      _tab = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _aller(0);
      },
      child: AdaptiveScaffold(
        maxContentWidth: double.infinity,
        currentIndex: _tab,
        onDestinationSelected: _aller,
        destinations: const [
          AdaptiveDestination(
            label: 'Accueil',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
          ),
          AdaptiveDestination(
            label: 'Gains',
            icon: Icons.payments_outlined,
            selectedIcon: Icons.payments_rounded,
          ),
          AdaptiveDestination(
            label: 'Profil',
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
          ),
        ],
        body: IndexedStack(
          index: _tab,
          children: [
            _visites.contains(0)
                ? ProviderHomeScreen(onOpenTab: _aller)
                : const SizedBox.shrink(),
            _visites.contains(1)
                ? KeyedSubtree(
                    key: ValueKey('gains-$_versionGains'),
                    child: const ProviderEarningsScreen(),
                  )
                : const SizedBox.shrink(),
            _visites.contains(2)
                ? KeyedSubtree(
                    key: ValueKey('profil-$_versionProfil'),
                    child: ProviderProfileScreen(onRetour: () => _aller(0)),
                  )
                : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}