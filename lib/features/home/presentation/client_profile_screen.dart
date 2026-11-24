import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/client_ui.dart';
import '../../requests/data/client_profile_service.dart';

/// Onglet Ã‚Â« Compte Ã‚Â» de l'espace client.
class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final ClientProfileService _service = ClientProfileService();
  ClientProfile? _profil;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _loading = true);
    final p = await _service.charger();
    if (!mounted) return;
    setState(() {
      _profil = p;
      _loading = false;
    });
  }

  Future<void> _deconnecter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se dÃƒÂ©connecter ?'),
        content: const Text('Vous pourrez vous reconnecter ÃƒÂ  tout moment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Se dÃƒÂ©connecter'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    // 1. DÃƒÂ©connexion explicite du client Supabase
    await Supabase.instance.client.auth.signOut();

    // 2. Nettoyage ÃƒÂ©ventuel du cache local du service
    try {
      await _service.deconnecter();
    } catch (_) {
      // Ignorer si le service ne fait rien de spÃƒÂ©cifique
    }

    if (!mounted) return;

    // 3. Redirection vers la page d'accueil / carte
    context.go('/');
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _profil == null
            ? Center(
                child: SingleChildScrollView(
                  child: ErrorState(
                    message: 'Impossible de charger votre profil.',
                    onRetry: _charger,
                  ),
                ),
              )
            : _contenu(_profil!),
      ),
    );
  }

  Widget _contenu(ClientProfile p) {
    final scheme = Theme.of(context).colorScheme;
    final gutter = context.gutter;
    final contact = [
      if ((p.phone ?? '').isNotEmpty) p.phone!,
      if ((p.email ?? '').isNotEmpty) p.email!,
    ].join(' Ã‚Â· ');

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          ContentWidth(
            maxWidth: 640,
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ClientPageTitle('Compte'),
                  const SizedBox(height: 12),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ IdentitÃƒÂ© Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  Row(
                    children: [
                      ClientAvatar(
                        name: p.nomAffiche,
                        photoUrl: p.photoUrl,
                        radius: 34,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.nomAffiche,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (contact.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  contact,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    color: context.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Points d'ÃƒÂ©toiles Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  ClientCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.stars_rounded,
                              size: 32,
                              color: AppColors.gold,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${p.starPoints} points d\'ÃƒÂ©toiles',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '+10 points par avis, +5 si votre commentaire fait '
                          'au moins 20 caractÃƒÂ¨res.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: context.textSecondary,
                          ),
                        ),
                        if (p.historique.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Divider(height: 1, color: scheme.outlineVariant),
                          for (final e in p.historique)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.libelle,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          _date(e.date),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: context.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${e.delta >= 0 ? '+' : ''}${e.delta}',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: context.readable(
                                        AppColors.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Raccourcis Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  ClientGroup(
                    children: [
                      ClientListRow(
                        icon: Icons.two_wheeler_rounded,
                        title: 'Mes courses',
                        onTap: () => context.push('/rides'),
                      ),
                      ClientListRow(
                        icon: Icons.local_hospital_outlined,
                        title: 'NumÃƒÂ©ros d\'urgence',
                        subtitle: 'Pompiers, police, hÃƒÂ´pital',
                        onTap: () => context.push('/emergency'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClientGroup(
                    children: [
                      ClientListRow(
                        icon: Icons.logout_rounded,
                        title: 'Se dÃƒÂ©connecter',
                        destructive: true,
                        trailing: const SizedBox.shrink(),
                        onTap: _deconnecter,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
