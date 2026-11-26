import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/client_ui.dart';
import '../data/mission_service.dart';
import '../domain/mission_model.dart';

/// Activité du client : ses demandes de dépannage (et l'accès à ses courses).
///
/// [embedded] = onglet de l'espace client (grand titre, sans barre d'app) ;
/// sinon écran ouvert seul (route /mes-demandes) avec flèche de retour.
class MesDemandesScreen extends StatefulWidget {
  const MesDemandesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MesDemandesScreen> createState() => _MesDemandesScreenState();
}

class _MesDemandesScreenState extends State<MesDemandesScreen> {
  final MissionService _service = MissionService();
  RealtimeChannel? _canal;
  List<Mission> _missions = [];
  bool _isLoading = true;
  bool _nonConnecte = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _charger();
    _canal = _service.ecouterMesMissions(() {
      if (mounted) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    final c = _canal;
    if (c != null) _service.arreter(c);
    super.dispose();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _nonConnecte = false;
      });
    }
    if (_service.currentUserId == null) {
      if (!mounted) return;
      setState(() {
        _missions = [];
        _nonConnecte = true;
        _isLoading = false;
      });
      return;
    }
    try {
      final uid = _service.currentUserId;
      final data = await _service.mesMissions();
      if (!mounted) return;
      setState(() {
        _missions = data.where((m) => m.clientId == uid).toList();
        _errorMessage = null;
      });
    } on MissionException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Connexion impossible. Vérifiez votre réseau et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Mes demandes'),
              leading: BackButton(
                onPressed: () {
                  // La carte MonTotem est l'accueil : on y revient toujours.
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                },
              ),
            ),
      body: widget.embedded ? SafeArea(bottom: false, child: _body()) : _body(),
    );
  }

  Widget _body() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // La page reste TOUJOURS complète : raccourcis visibles, et l'erreur
    // éventuelle s'affiche en encart interne (jamais un écran vide). Si le
    // chargement échoue, les demandes précédentes restent affichées.
    final gutter = context.gutter;
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
                  if (widget.embedded) const ClientPageTitle('Activité'),
                  if (widget.embedded) const SizedBox(height: 8),
                  const ClientSectionTitle('Raccourcis'),
                  const SizedBox(height: 8),
                  ClientGroup(
                    children: [
                      ClientListRow(
                        icon: Icons.two_wheeler_rounded,
                        title: 'Mes courses',
                        subtitle: 'Zémidjan, cloboto et kloboto',
                        onTap: () => context.push('/rides'),
                      ),
                      ClientListRow(
                        icon: Icons.add_circle_outline_rounded,
                        title: 'Nouvelle course',
                        subtitle: 'Commander un conducteur maintenant',
                        onTap: () => context.push('/ride/new'),
                      ),
                      ClientListRow(
                        icon: Icons.build_circle_outlined,
                        title: 'Trouver un dépanneur',
                        subtitle: 'Mécaniciens, vulcanisateurs, essence…',
                        onTap: () => context.push('/matching'),
                      ),
                    ],
                  ),
                  const ClientSectionTitle('Dépannages'),
                  if (_nonConnecte) ...[
                    const EmptyState(
                      icon: Icons.person_off_outlined,
                      title: 'Connectez-vous',
                      message:
                          'Connectez-vous pour retrouver vos demandes de '
                          'dépannage et leur suivi en direct.',
                    ),
                    FilledButton.icon(
                      onPressed: () => context.push('/login'),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Se connecter'),
                    ),
                  ] else if (_errorMessage != null)
                    _carteErreur()
                  else if (_missions.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Aucune demande pour le moment',
                      message: 'Vos demandes de dépannage apparaîtront ici.',
                    )
                  else
                    for (var i = 0; i < _missions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _carteMission(_missions[i]),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Encart d'erreur interne avec bouton Réessayer : la page reste
  /// complète (raccourcis visibles), on ne remplace jamais tout l'écran.
  Widget _carteErreur() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.error.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, color: scheme.error),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.35),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => _charger(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteMission(Mission m) {
    final couleur = m.status.couleur;
    return ClientCard(
      onTap: () => context.push('/mes-demandes/${m.id}'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              m.status.icone,
              color: context.readable(couleur),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.problem,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  m.providerName,
                  style: TextStyle(fontSize: 14, color: context.textSecondary),
                ),
                const SizedBox(height: 8),
                StatusPill(
                  label: m.status.libelle,
                  color: couleur,
                  icon: m.status.icone,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.textTertiary),
        ],
      ),
    );
  }
}
